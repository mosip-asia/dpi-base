#!/usr/bin/env bash
# ==============================================================================
# 🐮 DPI Center — Rancher Host Deployer (runs on the VM: /opt/rancher/deploy.sh)
# ==============================================================================
# Owns the application lifecycle on base-kube-ops-vm (AGENTS.md security rule 11):
# K3s, Helm, cert-manager and Rancher at the versions pinned in .env.template.
# Idempotent: a re-run with unchanged pins changes nothing; a bumped pin upgrades
# that component in place. It never recreates the VM.
#
# Invoked over IAP by base-kube-ops/remote-deploy.sh:
#   sudo env [CONFIRM_RANCHER_UPGRADE=yes] /opt/rancher/deploy.sh
#
# Exit codes: 0 deployed and healthy
#             1 failure
#             3 waiting for DNS: RANCHER_FQDN does not resolve to this VM yet.
#               K3s and cert-manager are in place; re-run once the CNAME exists.
# ==============================================================================
set -euo pipefail

# Cron-safe PATH (AGENTS.md rule 11) and the K3s kubeconfig for kubectl and helm
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:${PATH:-}"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# ------------------------------------------------------------------------------
# Formatting Helpers
# ------------------------------------------------------------------------------
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✔ [VM]${NC} $1"; }
log_cmd()  { echo -e "${CYAN}▶ [VM RUN]${NC} ${DIM}$1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ [VM WARN]${NC} $1"; }
log_fail() { echo -e "${RED}✖ [VM FAIL]${NC} $1"; }
TOTAL_STEPS=13
step() { echo -e "\n${BOLD}--- [$1/${TOTAL_STEPS}] $2 ---${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RANCHER_DIR="${RANCHER_DIR:-$SCRIPT_DIR}"

# ------------------------------------------------------------------------------
# Pure helpers (no side effects; exercised by local tests)
# ------------------------------------------------------------------------------

# rancher_version_change_allowed <installed> <target>
# Rancher supports upgrading from the latest patch of the running minor to the latest
# patch of the next minor, never skipping a minor, and never going back (rollback
# means restoring a backup). Prints the reason and returns 1 when the change is not allowed.
rancher_version_change_allowed() {
  local installed="${1%%-*}" target="${2%%-*}"
  local imaj imin ipat tmaj tmin tpat
  IFS=. read -r imaj imin ipat <<< "$installed"
  IFS=. read -r tmaj tmin tpat <<< "$target"
  if [[ ! "$imaj$imin$ipat$tmaj$tmin$tpat" =~ ^[0-9]+$ ]]; then
    echo "cannot parse versions '$1' and '$2'"
    return 1
  fi
  if (( tmaj != imaj )); then
    echo "major version change $1 -> $2 is not supported by this script"
    return 1
  fi
  if (( tmin < imin || (tmin == imin && tpat < ipat) )); then
    echo "downgrade $1 -> $2: Rancher only goes back by restoring a backup taken before the upgrade"
    return 1
  fi
  if (( tmin > imin + 1 )); then
    echo "skips a minor version ($1 -> $2): upgrade to the latest patch of $imaj.$((imin + 1)) first"
    return 1
  fi
  return 0
}

# last_a_record <dig output>: the final address of a dig +short answer (CNAME targets come first)
last_a_record() {
  printf '%s\n' "$1" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1 || true
}

# ------------------------------------------------------------------------------
# Deployment steps
# ------------------------------------------------------------------------------
sync_manifests() {
  step 1 "Syncing Manifests from /tmp"
  local f
  for f in .env.template rancher-values.yaml; do
    if [ -f "/tmp/$f" ]; then
      log_cmd "mv /tmp/$f $RANCHER_DIR/$f"
      mv "/tmp/$f" "$RANCHER_DIR/$f"
    fi
  done
  # No operator-owned staging files may linger (AGENTS.md rule 11)
  rm -f /tmp/.env.template /tmp/rancher-values.yaml /tmp/deploy.sh 2>/dev/null || true
}

load_config() {
  step 2 "Loading Configuration (.env.template, then .env overrides)"
  if [ -f "$RANCHER_DIR/.env.template" ]; then
    # shellcheck disable=SC1091
    source "$RANCHER_DIR/.env.template"
  fi
  if [ -f "$RANCHER_DIR/.env" ]; then
    # shellcheck disable=SC1091
    source "$RANCHER_DIR/.env"
  fi
  local v missing=""
  for v in RANCHER_FQDN RANCHER_BASE_FQDN ACME_EMAIL LETSENCRYPT_ENVIRONMENT K3S_VERSION HELM_VERSION \
           CERT_MANAGER_VERSION RANCHER_CHART_REPO RANCHER_CHART_REPO_URL RANCHER_CHART_VERSION \
           RANCHER_REPLICAS AGENT_TLS_MODE; do
    [ -n "${!v:-}" ] || missing="$missing $v"
  done
  if [ -n "$missing" ]; then
    log_fail "missing settings in $RANCHER_DIR/.env.template:$missing"
    exit 1
  fi
  log_info "Rancher ${RANCHER_CHART_VERSION} (${RANCHER_CHART_REPO}) on ${RANCHER_FQDN}; K3s ${K3S_VERSION}; cert-manager ${CERT_MANAGER_VERSION}; Helm ${HELM_VERSION}"
}

ensure_swap() {
  step 3 "Memory Protection (Swapfile Check)"
  if swapon --show | grep -q '/swapfile'; then
    log_info "2GB swapfile is active."
    return
  fi
  log_warn "Swap is not active (cloud-init should have created it). Configuring 2GB swapfile..."
  if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log_info "2GB swapfile activated."
}

# K3s names its node after the hostname it sees at start. On GCE the hostname changes twice
# during every boot (cloud-init sets the short name, then the guest agent sets the FQDN), so
# an unpinned K3s can register a second node after a reboot: the old node's pods are evicted
# after 5 minutes and stay "Terminating" forever (seen 2026-09-18). Pin the node name to the
# instance name through K3s's config file, which it reads at every start.
k3s_config() {
  local tmp
  K3S_NODE_NAME="$(curl -sf -H 'Metadata-Flavor: Google' \
    'http://metadata.google.internal/computeMetadata/v1/instance/name' || hostname | cut -d. -f1)"
  K3S_CONFIG_CHANGED=0
  install -d -m 0755 /etc/rancher/k3s
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
# Written by /opt/rancher/deploy.sh; K3s reads this file at every start.
node-name: "${K3S_NODE_NAME}"
write-kubeconfig-mode: "0600"
EOF
  if ! cmp -s "$tmp" /etc/rancher/k3s/config.yaml; then
    install -m 0644 "$tmp" /etc/rancher/k3s/config.yaml
    K3S_CONFIG_CHANGED=1
  fi
  rm -f "$tmp"
}

# Node objects left behind by earlier hostname changes: deleting them also removes their
# stuck pods. A single-node cluster by design, so any other node object is stale.
remove_stale_nodes() {
  local n ready
  for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    [ "$n" = "$K3S_NODE_NAME" ] && continue
    ready="$(kubectl get node "$n" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [ "$ready" = "True" ]; then
      log_warn "Unexpected second Ready node ${n}: left in place, please investigate."
      continue
    fi
    log_warn "Deleting stale node object ${n} (its Terminating pods go with it)."
    kubectl delete node "$n" --timeout=60s
  done
}

ensure_k3s() {
  step 4 "K3s ${K3S_VERSION}"
  local current="none"
  k3s_config
  if command -v k3s >/dev/null 2>&1; then
    current="$(k3s --version 2>/dev/null | awk 'NR==1 {print $3}' || true)"
  fi
  if [ "$current" = "$K3S_VERSION" ]; then
    log_info "K3s ${K3S_VERSION} already installed (node name ${K3S_NODE_NAME})."
    if [ "$K3S_CONFIG_CHANGED" = "1" ]; then
      log_cmd "systemctl restart k3s   (config.yaml changed; running pods are kept)"
      systemctl restart k3s
    fi
  else
    log_info "Installing K3s ${K3S_VERSION} (current: ${current}, node name ${K3S_NODE_NAME})..."
    log_cmd "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} sh -s - server"
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" INSTALL_K3S_EXEC="server" sh -s -
  fi
  log_info "Waiting for node ${K3S_NODE_NAME} and Traefik..."
  timeout 300 bash -c "until [ \"\$(kubectl get node '$K3S_NODE_NAME' -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" = True ]; do sleep 5; done"
  remove_stale_nodes
  timeout 300 bash -c 'until kubectl -n kube-system get deploy traefik >/dev/null 2>&1; do sleep 5; done'
  kubectl -n kube-system rollout status deploy/traefik --timeout=300s
}

operator_kubeconfig() {
  step 5 "Operator Kubeconfig for 'ubuntu'"
  install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.kube
  install -m 0600 -o ubuntu -g ubuntu /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  # K3s's kubectl ignores ~/.kube/config unless KUBECONFIG is set: without it, a non-root user
  # gets "permission denied" on /etc/rancher/k3s/k3s.yaml. ssh.sh opens login shells, which read this.
  cat > /etc/profile.d/k3s-kubeconfig.sh <<'EOF'
# Written by /opt/rancher/deploy.sh
if [ -r "$HOME/.kube/config" ]; then
  export KUBECONFIG="$HOME/.kube/config"
fi
EOF
  chmod 0644 /etc/profile.d/k3s-kubeconfig.sh
  log_info "/home/ubuntu/.kube/config (0600) and KUBECONFIG for login shells: kubectl and helm work in ./base-kube-ops/ssh.sh sessions."
}

ensure_helm() {
  step 6 "Helm ${HELM_VERSION}"
  if command -v helm >/dev/null 2>&1 && [ "$(helm version --short 2>/dev/null | cut -d+ -f1)" = "$HELM_VERSION" ]; then
    log_info "Helm ${HELM_VERSION} already installed."
    return
  fi
  local tmp
  tmp="$(mktemp -d)"
  log_cmd "download helm-${HELM_VERSION}-linux-amd64.tar.gz and verify its sha256"
  curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o "$tmp/helm.tgz"
  curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" -o "$tmp/helm.sha"
  (cd "$tmp" && sed 's#  .*#  helm.tgz#' helm.sha | sha256sum -c -)
  tar -xzf "$tmp/helm.tgz" -C "$tmp"
  install -m 0755 "$tmp/linux-amd64/helm" /usr/local/bin/helm
  rm -rf "$tmp"
  log_info "Helm ${HELM_VERSION} installed."
}

ensure_cert_manager() {
  step 7 "cert-manager ${CERT_MANAGER_VERSION}"
  helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
  helm repo update jetstack >/dev/null
  log_cmd "helm upgrade --install cert-manager jetstack/cert-manager --version ${CERT_MANAGER_VERSION}"
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --version "$CERT_MANAGER_VERSION" \
    --set crds.enabled=true \
    --wait --timeout 10m
  log_info "cert-manager ${CERT_MANAGER_VERSION} ready."
}

dns_gate() {
  step 8 "DNS Gate (${RANCHER_FQDN} must resolve to this VM)"
  local my_ip g c base
  my_ip="$(curl -sf -H 'Metadata-Flavor: Google' \
    'http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip' || true)"
  g="$(last_a_record "$(dig +short A "$RANCHER_FQDN" @8.8.8.8 2>/dev/null || true)")"
  c="$(last_a_record "$(dig +short A "$RANCHER_FQDN" @1.1.1.1 2>/dev/null || true)")"
  if [ -n "$my_ip" ] && [ "$g" = "$my_ip" ] && [ "$c" = "$my_ip" ]; then
    log_info "${RANCHER_FQDN} -> ${my_ip} on Google and Cloudflare."
    return
  fi
  base="$(last_a_record "$(dig +short A "$RANCHER_BASE_FQDN" @8.8.8.8 2>/dev/null || true)")"
  log_warn "${RANCHER_FQDN} does not resolve to this VM yet (VM ${my_ip:-unknown}, Google ${g:-none}, Cloudflare ${c:-none})."
  log_warn "${RANCHER_BASE_FQDN} -> ${base:-none} (the A record from base-kube-ops/terraform/dns.tf)."
  echo "  Rancher is installed only once its server URL resolves, because Let's Encrypt validates that name"
  echo "  and downstream clusters store it. Ask for the CNAME in parent zone dpi-center (ait-brainlab-mgmt):"
  echo "    ${RANCHER_FQDN}. 300 IN CNAME ${RANCHER_BASE_FQDN}."
  echo "  K3s and cert-manager are in place. Re-run ./base-kube-ops/remote-deploy.sh once the name resolves."
  exit 3
}

ensure_rancher() {
  step 9 "Rancher ${RANCHER_CHART_VERSION} (${RANCHER_CHART_REPO})"
  local installed reason
  installed="$(helm -n cattle-system list --filter '^rancher$' -o json 2>/dev/null | jq -r '.[0].chart // empty' | sed 's/^rancher-//' || true)"
  if [ -n "$installed" ] && [ "$installed" != "$RANCHER_CHART_VERSION" ]; then
    if ! reason="$(rancher_version_change_allowed "$installed" "$RANCHER_CHART_VERSION")"; then
      log_fail "Refusing Rancher version change: ${reason}."
      exit 1
    fi
    if [ "${CONFIRM_RANCHER_UPGRADE:-}" != "yes" ]; then
      log_fail "Rancher ${installed} -> ${RANCHER_CHART_VERSION} is a one-way upgrade. Take a disk snapshot first"
      echo "  (README: Upgrades), then re-run: ./base-kube-ops/remote-deploy.sh --confirm-rancher-upgrade"
      exit 1
    fi
    log_warn "Upgrading Rancher ${installed} -> ${RANCHER_CHART_VERSION} (confirmed)."
  fi
  helm repo add "$RANCHER_CHART_REPO" "$RANCHER_CHART_REPO_URL" --force-update >/dev/null
  helm repo update "$RANCHER_CHART_REPO" >/dev/null
  log_cmd "helm upgrade --install rancher ${RANCHER_CHART_REPO}/rancher --version ${RANCHER_CHART_VERSION}"
  helm upgrade --install rancher "${RANCHER_CHART_REPO}/rancher" \
    --namespace cattle-system --create-namespace \
    --version "$RANCHER_CHART_VERSION" \
    -f "$RANCHER_DIR/rancher-values.yaml" \
    --set hostname="$RANCHER_FQDN" \
    --set replicas="$RANCHER_REPLICAS" \
    --set letsEncrypt.email="$ACME_EMAIL" \
    --set letsEncrypt.environment="$LETSENCRYPT_ENVIRONMENT" \
    --set agentTLSMode="$AGENT_TLS_MODE" \
    --wait --timeout 15m
  kubectl -n cattle-system rollout status deploy/rancher --timeout=15m
}

# The base name (our own A record) gets a certificate and a permanent redirect to the server
# URL: Rancher's Google sign-in and the downstream agents work on one hostname only. Skipped
# when both names are the same (for example a temporary override in .env).
ensure_base_redirect() {
  step 10 "Base-name redirect (${RANCHER_BASE_FQDN} -> https://${RANCHER_FQDN})"
  if [ "$RANCHER_BASE_FQDN" = "$RANCHER_FQDN" ]; then
    log_warn "RANCHER_BASE_FQDN equals RANCHER_FQDN: no redirect; removing one if present."
    kubectl -n cattle-system delete ingress,middlewares.traefik.io rancher-base-redirect --ignore-not-found
    return
  fi
  local base_re
  base_re="$(printf '%s' "$RANCHER_BASE_FQDN" | sed 's/\./\\./g')"   # dots are literal in the regex
  log_cmd "kubectl apply: Middleware and Ingress rancher-base-redirect (certificate from Issuer rancher)"
  kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rancher-base-redirect
  namespace: cattle-system
spec:
  redirectRegex:
    regex: '^https?://${base_re}(/.*)?\$'
    replacement: 'https://${RANCHER_FQDN}\${1}'
    permanent: true
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rancher-base-redirect
  namespace: cattle-system
  annotations:
    cert-manager.io/issuer: rancher
    cert-manager.io/issuer-kind: Issuer
    traefik.ingress.kubernetes.io/router.middlewares: cattle-system-rancher-base-redirect@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
    - host: ${RANCHER_BASE_FQDN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: rancher
                port:
                  number: 80
  tls:
    - hosts:
        - ${RANCHER_BASE_FQDN}
      secretName: tls-rancher-base-redirect
EOF
}

certificate_gate() {
  step 11 "Certificate Gate (Let's Encrypt ${LETSENCRYPT_ENVIRONMENT})"
  local deadline
  deadline=$(( $(date +%s) + 600 ))
  until [ "$(kubectl -n cattle-system get certificate tls-rancher-ingress \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      kubectl get certificate,certificaterequest,order,challenge -A 2>/dev/null || true
      log_fail "Certificate not Ready after 10 minutes: are 80 and 443 reachable from the internet? Let's Encrypt rate limit?"
      exit 1
    fi
    sleep 15
  done
  log_info "Certificate tls-rancher-ingress is Ready."
  if [ "$RANCHER_BASE_FQDN" != "$RANCHER_FQDN" ]; then
    deadline=$(( $(date +%s) + 300 ))
    until [ "$(kubectl -n cattle-system get certificate tls-rancher-base-redirect         -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; do
      if [ "$(date +%s)" -ge "$deadline" ]; then
        log_warn "Certificate tls-rancher-base-redirect not Ready after 5 minutes; the redirect works, but with Traefik's default certificate until it is."
        break
      fi
      sleep 15
    done
    [ "$(date +%s)" -lt "$deadline" ] && log_info "Certificate tls-rancher-base-redirect is Ready."
  fi
}

health_check() {
  step 12 "Health Check (through the loopback: GCE has no hairpin NAT)"
  local code issuer redirect
  code="$(curl -sk --max-time 15 --resolve "${RANCHER_FQDN}:443:127.0.0.1" -o /dev/null -w '%{http_code}' \
    "https://${RANCHER_FQDN}/healthz" || true)"
  if [ "$code" != "200" ]; then
    log_fail "https://${RANCHER_FQDN}/healthz returned ${code:-no answer}"
    exit 1
  fi
  issuer="$(openssl s_client -servername "$RANCHER_FQDN" -connect 127.0.0.1:443 </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer 2>/dev/null || true)"
  log_info "/healthz 200; certificate ${issuer:-issuer unknown}"
  if [ "$LETSENCRYPT_ENVIRONMENT" = "production" ] && printf '%s' "$issuer" | grep -q STAGING; then
    log_warn "A STAGING certificate is still served although production is configured; it renews to production shortly."
  fi
  if [ "$RANCHER_BASE_FQDN" != "$RANCHER_FQDN" ]; then
    redirect="$(curl -sk --max-time 15 --resolve "${RANCHER_BASE_FQDN}:443:127.0.0.1" -o /dev/null       -w '%{http_code} %{redirect_url}' "https://${RANCHER_BASE_FQDN}/" || true)"
    case "$redirect" in
      "301 https://${RANCHER_FQDN}/"*) log_info "https://${RANCHER_BASE_FQDN}/ -> ${redirect}" ;;
      *) log_warn "https://${RANCHER_BASE_FQDN}/ answered '${redirect:-nothing}' instead of 301 to https://${RANCHER_FQDN}/" ;;
    esac
  fi
}

finish() {
  step 13 "Ownership & Summary"
  chown -R ubuntu:ubuntu "$RANCHER_DIR"
  chmod 0755 "$RANCHER_DIR/deploy.sh"
  chmod 0644 "$RANCHER_DIR/.env.template" "$RANCHER_DIR/rancher-values.yaml"
  if [ -f "$RANCHER_DIR/.env" ]; then chmod 0600 "$RANCHER_DIR/.env"; fi
  echo -e "\n${BOLD}--- Components ---${NC}"
  k3s --version | awk 'NR==1'
  helm list -A
  echo -e "\n${BOLD}--- Rancher ---${NC}"
  echo "  URL: https://${RANCHER_FQDN}"
  if [ "$RANCHER_BASE_FQDN" != "$RANCHER_FQDN" ]; then
    echo "  Base name: https://${RANCHER_BASE_FQDN} (redirects to the URL above)"
  fi
  # Before the first login the setting has no value yet; its default ("true") applies.
  local first_login
  first_login="$(kubectl get settings.management.cattle.io first-login -o jsonpath='{.value}' 2>/dev/null || true)"
  if [ -z "$first_login" ]; then
    first_login="$(kubectl get settings.management.cattle.io first-login -o jsonpath='{.default}' 2>/dev/null || true)"
  fi
  if [ "$first_login" = "true" ]; then
    echo "  First login pending. Read the generated bootstrap password once, in your own terminal:"
    cat <<'EOF'
    ./base-kube-ops/ssh.sh "kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{\"\n\"}}'"
EOF
    echo "  Paste it only into the Rancher login page, then set the admin password (12+ characters)."
  fi
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    log_fail "run as root: sudo ${RANCHER_DIR}/deploy.sh"
    exit 1
  fi
  sync_manifests
  load_config
  ensure_swap
  ensure_k3s
  operator_kubeconfig
  ensure_helm
  ensure_cert_manager
  dns_gate
  ensure_rancher
  ensure_base_redirect
  certificate_gate
  health_check
  finish
}

# Run only when executed, so the pure helpers above can be sourced by tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
