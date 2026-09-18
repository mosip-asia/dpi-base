#!/usr/bin/env bash
# ==============================================================================
# base-kube-ops — throwaway K3s VM, startup script (rehearsal_k3s_startup.sh)
# ==============================================================================
# Runs on the rehearsal VM that scripts/rehearsal_k3s.sh creates (README:
# "Downstream autonomy rehearsal"). Installs a single-node K3s with Traefik and
# the service load balancer disabled (nothing listens on 80/443 although the VM
# carries the Rancher network tag) and a one-minute heartbeat to the serial
# console, so the laptop can follow the cluster without SSH while the Rancher
# VM is off.
#
# Markers (serial console port 1, read by rehearsal_k3s.sh wait / status):
#   DPI-REHEARSAL: START ... | READY node=... | FAILED step=...
#   DPI-REHEARSAL: HEARTBEAT <time> node=<Ready|NotReady|none> agent=<pod status|absent>
#                            rehearsal=<ready>/<wanted> rancher=<http code|down>
# Inputs: instance metadata `k3s-version` and `rancher-host`. Nothing secret.
# Idempotent: a reboot re-runs it and every step is a no-op.
# ==============================================================================
set -euo pipefail

md() { curl -sf -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" || true; }
K3S_VERSION="$(md k3s-version)"
RANCHER_HOST="$(md rancher-host)"
LOG_FILE=/var/log/dpi-rehearsal.log
STEP=start
exec > >(tee -a "${LOG_FILE}") 2>&1

marker() { echo "DPI-REHEARSAL: $1 $(date -Is)"; }
trap 'marker "FAILED step=${STEP}"' ERR

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH="/usr/local/bin:${PATH}"

marker "START k3s=${K3S_VERSION:-latest} rancher-host=${RANCHER_HOST:-unset}"
timedatectl set-timezone Asia/Bangkok || true

# ------------------------------------------------------------------ 1 k3s
STEP=k3s
# The node name is pinned like on the Rancher host: the GCE hostname changes during boot.
install -d -m 0755 /etc/rancher/k3s
if [ ! -f /etc/rancher/k3s/config.yaml ]; then
  printf 'node-name: "%s"\nwrite-kubeconfig-mode: "0600"\n' "$(curl -sf -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name || hostname | cut -d. -f1)" > /etc/rancher/k3s/config.yaml
fi
if ! command -v k3s >/dev/null 2>&1 || { [ -n "${K3S_VERSION}" ] && ! k3s --version | grep -q "${K3S_VERSION}"; }; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_EXEC="server --disable traefik --disable servicelb" sh -s -
fi
timeout 300 bash -c 'until kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 5; done'
timeout 300 bash -c 'until kubectl -n kube-system get deploy coredns >/dev/null 2>&1; do sleep 5; done'
kubectl -n kube-system rollout status deploy/coredns --timeout=300s

# ------------------------------------------------------------------ 2 heartbeat
# A systemd timer, once a minute, writes one line straight to the serial
# console (/dev/ttyS0) and to the log: node state, the Rancher agent pod,
# the rehearsal deployment, and whether Rancher answers from here.
STEP=heartbeat
cat > /usr/local/bin/dpi-rehearsal-heartbeat <<'EOF'
#!/usr/bin/env bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH="/usr/local/bin:${PATH}"
host="$(curl -sf -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/rancher-host || true)"
node=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -n1); node=${node:-none}
agent=$(kubectl -n cattle-system get pods -l app=cattle-cluster-agent --no-headers 2>/dev/null | awk '{print $3}' | head -n1); agent=${agent:-absent}
ready=$(kubectl -n rehearsal get deploy rehearsal-nginx -o jsonpath='{.status.readyReplicas}' 2>/dev/null); ready=${ready:-0}
wanted=$(kubectl -n rehearsal get deploy rehearsal-nginx -o jsonpath='{.spec.replicas}' 2>/dev/null); wanted=${wanted:-0}
if [ -n "${host}" ]; then
  rancher=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "https://${host}/healthz" 2>/dev/null || true)
  if [ -z "${rancher}" ] || [ "${rancher}" = "000" ]; then rancher=down; fi
else
  rancher=unset
fi
line="DPI-REHEARSAL: HEARTBEAT $(date -Is) node=${node} agent=${agent} rehearsal=${ready}/${wanted} rancher=${rancher}"
echo "${line}" > /dev/ttyS0 2>/dev/null || true
echo "${line}" >> /var/log/dpi-rehearsal.log
EOF
chmod 0755 /usr/local/bin/dpi-rehearsal-heartbeat

cat > /etc/systemd/system/dpi-rehearsal-heartbeat.service <<'EOF'
[Unit]
Description=base-kube-ops rehearsal heartbeat to the serial console

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dpi-rehearsal-heartbeat
EOF

cat > /etc/systemd/system/dpi-rehearsal-heartbeat.timer <<'EOF'
[Unit]
Description=base-kube-ops rehearsal heartbeat, every minute

[Timer]
OnBootSec=30
OnUnitActiveSec=60
AccuracySec=5

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now dpi-rehearsal-heartbeat.timer

# ------------------------------------------------------------------ 3 done
STEP=done
/usr/local/bin/dpi-rehearsal-heartbeat || true
marker "READY node=$(kubectl get nodes --no-headers | awk '{print $1}' | head -n1) k3s=$(k3s --version | head -n1 | awk '{print $3}')"
