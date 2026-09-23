#!/usr/bin/env bash
# ==============================================================================
# base-kube-ops — downstream-autonomy rehearsal kit (rehearsal_k3s.sh)
# ==============================================================================
# Proves what the instance schedule relies on: a downstream cluster imported into
# Rancher keeps working while the Rancher VM is off and reconnects by itself when
# it is back. It also proves the import path with the production certificate and
# agentTLSMode system-store (no cacerts). A throwaway single-node K3s VM in this
# project is imported, the Rancher VM is stopped by hand, the throwaway keeps
# taking work on its own kubeconfig, the Rancher VM is started and the cluster
# returns to Active, then the throwaway is deleted. One sub-command per step:
#
#   create         create the throwaway VM (e2-medium, Ubuntu 24.04, K3s)      [mutates]
#   wait           follow its serial console until READY                       [read-only]
#   status         both VMs, markers, last heartbeat, Rancher, agent TLS mode  [read-only]
#   ssh-check      first SSH through IAP: hostname, sudo, kubectl get nodes    [OS Login key]
#   import         run Rancher's registration command on the throwaway         [mutates]
#   probe          on the throwaway: nodes, a new deployment, wait for it      [mutates it]
#   rancher-stop   gcloud compute instances stop base-kube-ops-vm              [mutates]
#   rancher-start  start base-kube-ops-vm and wait for /healthz (not 17:45-18:45 BKK);
#                  --retry [min] keeps trying while the zone has no capacity;
#                  --any-type tries other 4-vCPU families on the same disk       [mutates]
#   rancher-machine-type <type>  change the stopped Rancher VM's type            [mutates]
#   delete         delete the throwaway VM and the local registration file     [mutates]
#   forget         remove the rehearsal cluster from Rancher (over IAP)        [mutates Rancher]
#   verify-clean   throwaway gone, cluster forgotten, cacerts empty            [read-only]
#
# The registration command (a bearer token) is pasted into
# base-kube-ops/.local/rancher-import.secret (git-ignored through *.secret),
# copied to the throwaway over IAP and never printed, never put on a command line.
# create tries the region's zones and a second machine type when a zone is out of
# capacity; REHEARSAL_ZONES / REHEARSAL_MACHINES (space-separated) override them.
# ==============================================================================

if grep -qi 'microsoft' /proc/version 2>/dev/null; then
  echo "  FAIL  this is WSL's bash, not Git Bash. Open a Git Bash terminal, or from PowerShell run:"
  echo "        & 'C:\\Program Files\\Git\\bin\\bash.exe' base-kube-ops/scripts/rehearsal_k3s.sh <sub-command>"
  exit 1
fi
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KO_ROOT="$(cd "${HERE}/.." && pwd)"
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# Names and pins come from the same file the deployer uses.
ENV_TEMPLATE="${KO_ROOT}/rancher/.env.template"
if [ -f "${ENV_TEMPLATE}" ]; then
  TMP_ENV="$(mktemp)"; tr -d '\r' < "${ENV_TEMPLATE}" > "${TMP_ENV}"
  set -a
  # shellcheck disable=SC1090
  . "${TMP_ENV}"
  set +a
  rm -f "${TMP_ENV}"
fi

PROJECT="base-kube-ops"
ZONE="asia-southeast1-b"
NETWORK="default"
RANCHER_VM="base-kube-ops-vm"
RANCHER_HOST="${RANCHER_FQDN:-rancher.dpi.ait.ac.th}"
RANCHER_URL="https://${RANCHER_HOST}"
K3S_VERSION="${K3S_VERSION:-v1.36.3+k3s1}"
DEFAULT_MACHINE_TYPE="e2-standard-4"      # the Rancher VM's Terraform default (variables.tf)

VM="base-kube-ops-throwaway"
TAG="base-kube-ops-node"          # same tag as the Rancher VM: 22 through IAP only, 22/3389 denied from the internet
MACHINE="e2-medium"               # 2 vCPU / 4 GB: K3s plus the Rancher agents without swapping
DISK_GB=20
IMAGE_FAMILY="ubuntu-2404-lts-amd64"
IMAGE_PROJECT="ubuntu-os-cloud"
STARTUP="${HERE}/rehearsal_k3s_startup.sh"
IMPORT_FILE="${KO_ROOT}/.local/rancher-import.secret"
HEALTH="${HERE}/check_rancher_health.sh"
CLUSTER_NAME="rehearsal-k3s"

FAILED=0
pass(){ echo "  PASS  $1"; }
fail(){ echo "  FAIL  $1"; FAILED=1; }
warn(){ echo "  WARN  $1"; }
info(){ echo "  ....  $1"; }
bkk_now(){ date -u -d '+7 hours' '+%H:%M'; }                     # Bangkok = UTC+7, no DST
in_stop_window(){ local t; t="$(bkk_now)"; [[ "${t}" > "17:44" && "${t}" < "18:46" ]]; }
winpath(){ if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
serial(){ gcloud compute instances get-serial-port-output "$1" --zone "${2:-${ZONE}}" --project "${PROJECT}" --port 1 2>/dev/null | tr -d '\r'; }
vm_status(){ gcloud compute instances describe "$1" --zone "${2:-${ZONE}}" --project "${PROJECT}" --format='value(status)' 2>/dev/null | tr -d '\r'; }
# The throwaway may land in another zone of the region when the first one is out of capacity: find it by name.
tw_zone(){ local z; z="$(gcloud compute instances list --project "${PROJECT}" --filter="name=${VM}" --format='value(zone.basename())' 2>/dev/null | tr -d '\r' | head -n1)"; printf '%s' "${z:-${ZONE}}"; }
tw_status(){ gcloud compute instances list --project "${PROJECT}" --filter="name=${VM}" --format='value(status)' 2>/dev/null | tr -d '\r' | head -n1; }
# SSH and SCP through Identity-Aware Proxy. On Windows gcloud drives its bundled plink/pscp and answers the
# host-key prompt itself (property ssh/putty_force_connect, on by default), so this works from a script.
# Remote commands run as the OS Login user with plain sudo (no "sudo -i"), so "$" inside them is safe.
ssh_run(){ gcloud compute ssh "${VM}" --zone "$(tw_zone)" --project "${PROJECT}" --tunnel-through-iap --command "$1" 2>&1 | tr -d '\r' | grep -vE '^(y|)$'; }
scp_put(){ gcloud compute scp "$(winpath "$1")" "${VM}:$2" --zone "$(tw_zone)" --project "${PROJECT}" --tunnel-through-iap; }
rssh_run(){ gcloud compute ssh "${RANCHER_VM}" --zone "${ZONE}" --project "${PROJECT}" --tunnel-through-iap --command "$1" 2>&1 | tr -d '\r' | grep -vE '^(y|)$'; }
rancher_code(){ curl -s --max-time 10 -o /dev/null -w '%{http_code}' "${RANCHER_URL}/healthz" 2>/dev/null || true; }
cacerts_bytes(){ curl -s --max-time 10 "${RANCHER_URL}/cacerts" 2>/dev/null | wc -c | tr -d ' '; }

# ------------------------------------------------------------------------------
cmd_create(){
  [ -f "${STARTUP}" ] || { fail "missing ${STARTUP}"; return 1; }
  local st t z m out
  st="$(tw_status)"
  [ -z "${st}" ] || { warn "${VM} already exists (${st}, zone $(tw_zone)); nothing created — next: wait / ssh-check"; return 0; }
  [ "$(vm_status "${RANCHER_VM}")" = "RUNNING" ] || warn "${RANCHER_VM} is not RUNNING; the import step needs Rancher up"
  t="$(bkk_now)"
  [[ "${t}" > "17:14" ]] && warn "Bangkok ${t}: a rehearsal takes ~45 min and no Rancher start is allowed 17:45-18:45 on weekdays; consider the next weekday morning"
  # A zone can be out of capacity for a machine type (ZONE_RESOURCE_POOL_EXHAUSTED). The throwaway only needs
  # the same VPC, so try the region's zones and a second machine type; every later sub-command finds it by name.
  for z in ${REHEARSAL_ZONES:-${ZONE} asia-southeast1-a asia-southeast1-c}; do
    for m in ${REHEARSAL_MACHINES:-${MACHINE} e2-standard-2}; do
      info "trying ${m} in ${z}"
      if out="$(gcloud compute instances create "${VM}" --zone "${z}" --project "${PROJECT}" \
          --machine-type "${m}" --image-family "${IMAGE_FAMILY}" --image-project "${IMAGE_PROJECT}" \
          --boot-disk-size "${DISK_GB}GB" --boot-disk-type pd-balanced \
          --network "${NETWORK}" --tags "${TAG}" \
          --no-service-account --no-scopes \
          --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
          --metadata "enable-oslogin=TRUE,block-project-ssh-keys=TRUE,k3s-version=${K3S_VERSION},rancher-host=${RANCHER_HOST}" \
          --metadata-from-file "startup-script=$(winpath "${STARTUP}")" \
          --labels "component=base-kube-ops-rehearsal" \
          --description "base-kube-ops rehearsal: throwaway K3s, delete after the rehearsal" 2>&1)"; then
        printf '%s\n' "${out}" | tr -d '\r' | grep -E "^(NAME|${VM})" | sed 's/^/  /'
        pass "${VM} created (${m} in ${z}, ${DISK_GB} GB, tag ${TAG}, no service account)"
        info "next: ./base-kube-ops/scripts/rehearsal_k3s.sh wait"
        return 0
      elif printf '%s' "${out}" | grep -q 'ZONE_RESOURCE_POOL_EXHAUSTED'; then
        warn "no ${m} capacity in ${z} right now"
      else
        printf '%s\n' "${out}" | tr -d '\r' | tail -n 5 | sed 's/^/    /'
        fail "create failed for a reason other than capacity — stopping"
        return 1
      fi
    done
  done
  fail "no capacity for ${REHEARSAL_MACHINES:-${MACHINE} e2-standard-2} in ${REHEARSAL_ZONES:-${ZONE} asia-southeast1-a asia-southeast1-c}; try later, or set REHEARSAL_ZONES / REHEARSAL_MACHINES"
  return 1
}

cmd_wait(){
  local deadline last line z
  z="$(tw_zone)"
  deadline=$(( $(date +%s) + 600 )); last=""
  echo "following ${VM} startup markers (zone ${z}, timeout 10 min)"
  while :; do
    line="$(serial "${VM}" "${z}" | grep -E 'DPI-REHEARSAL: (START|READY|FAILED)' | tail -n1 || true)"
    if [ -n "${line}" ] && [ "${line}" != "${last}" ]; then echo "  ${line}"; last="${line}"; fi
    case "${line}" in
      *"DPI-REHEARSAL: FAILED"*) echo "startup failed; last 30 serial lines:"; serial "${VM}" "${z}" | tail -n 30 | sed 's/^/    /'; return 1 ;;
      *"DPI-REHEARSAL: READY"*)  pass "K3s ready on ${VM}"; info "next: ./base-kube-ops/scripts/rehearsal_k3s.sh ssh-check"; return 0 ;;
    esac
    [ "$(date +%s)" -ge "${deadline}" ] && { fail "timeout (last marker: ${last:-none})"; return 1; }
    sleep 20
  done
}

cmd_status(){
  local s code n mode
  echo "Instances (${PROJECT})"
  gcloud compute instances list --project "${PROJECT}" --filter="name~^base-kube-ops-" \
    --format="table(name,zone.basename(),machineType.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null | sed 's/^/  /'
  echo "Throwaway (${VM})"
  s="$(serial "${VM}" "$(tw_zone)")"
  if [ -z "${s}" ]; then
    info "no serial output (absent, or created seconds ago)"
  else
    printf '%s\n' "${s}" | grep -E 'DPI-REHEARSAL: (START|READY|FAILED)' | tail -n 3 | sed 's/^.*DPI-REHEARSAL:/  DPI-REHEARSAL:/'
    printf '%s\n' "${s}" | grep 'DPI-REHEARSAL: HEARTBEAT' | tail -n 1 | sed 's/^.*DPI-REHEARSAL:/  last: DPI-REHEARSAL:/'
  fi
  echo "Rancher (${RANCHER_URL})"
  code="$(rancher_code)"
  if [ "${code}" = "200" ]; then
    pass "/healthz -> 200 (Bangkok $(bkk_now))"
    n="$(cacerts_bytes)"
    [ "${n:-0}" = "0" ] && info "cacerts setting is empty (expected with a public certificate)" || warn "cacerts setting is SET (${n} bytes)"
    mode="$(rssh_run "sudo k3s kubectl get settings.management.cattle.io agent-tls-mode -o jsonpath='{.value}'" | tail -n1)"
    info "agent-tls-mode: ${mode:-unknown}"
    rssh_run "sudo k3s kubectl get clusters.management.cattle.io -o custom-columns='ID:.metadata.name,NAME:.spec.displayName,READY:.status.conditions[?(@.type==\"Ready\")].status' --no-headers" | sed 's/^/  cluster: /'
  else
    warn "/healthz -> ${code:-no answer} (stopped? Bangkok $(bkk_now))"
  fi
}

cmd_ssh_check(){
  info "first SSH to ${VM} through IAP (Windows: plink; the host key is accepted by gcloud itself)"
  ssh_run 'echo host: $(hostname); if sudo -n true 2>/dev/null; then echo sudo: ok; else echo sudo: DENIED - the account needs roles/compute.osAdminLogin; fi; sudo k3s kubectl get nodes' \
    && pass "SSH works" || fail "SSH failed (IAP role? firewall base-kube-ops-allow-iap-ssh?)"
  info "next: Rancher → Cluster Management → Import Existing → Generic → name ${CLUSTER_NAME} → Create; copy the"
  info "      plain 'curl -sfL … | kubectl apply -f -' command (not the --insecure one) into ${IMPORT_FILE#"${KO_ROOT}"/}; then: import"
}

cmd_import(){
  [ -f "${IMPORT_FILE}" ] || { fail "missing ${IMPORT_FILE#"${KO_ROOT}"/} — paste Rancher's 'curl -sfL … | kubectl apply -f -' command into it"; return 1; }
  git -C "${KO_ROOT}" check-ignore -q "${IMPORT_FILE}" || { fail "${IMPORT_FILE} is NOT ignored by git — stop and fix .gitignore first"; return 1; }
  local url tmp
  url="$(tr -d '\r' < "${IMPORT_FILE}" | grep -oE 'https://[^[:space:]"'"'"']+/v3/import/[^[:space:]"'"'"']+' | head -n1 || true)"
  [ -n "${url}" ] || { fail "no https://…/v3/import/… URL found in the file"; return 1; }
  case "${url}" in "https://${RANCHER_HOST}/"*) : ;; *) warn "the registration URL is not on ${RANCHER_HOST}" ;; esac
  [ "$(rancher_code)" = "200" ] || { fail "Rancher does not answer at ${RANCHER_URL}; the agent could not register"; return 1; }
  mkdir -p "${KO_ROOT}/.local"
  tmp="$(mktemp "${KO_ROOT}/.local/import-url.XXXXXX")"
  printf '%s\n' "${url}" > "${tmp}"
  info "registration URL found (not shown); copying it to ${VM} over IAP, then applying with a plain curl (public certificate)"
  scp_put "${tmp}" "rancher-import.txt"; local rc=$?
  rm -f "${tmp}"
  [ "${rc}" = 0 ] || { fail "scp failed"; return 1; }
  ssh_run 'set -o pipefail; url=$(cat rancher-import.txt); rm -f rancher-import.txt; [ -n "$url" ] || { echo no url received; exit 1; }; curl -sfL "$url" | sudo k3s kubectl apply -f - || exit 1; for i in $(seq 1 24); do sudo k3s kubectl -n cattle-system get deploy cattle-cluster-agent >/dev/null 2>&1 && break; sleep 5; done; sudo k3s kubectl -n cattle-system rollout status deploy/cattle-cluster-agent --timeout=300s; sudo k3s kubectl -n cattle-system get pods; echo agent-env:; sudo k3s kubectl -n cattle-system set env deploy/cattle-cluster-agent --list | grep -E "^(CATTLE_SERVER|CATTLE_CA_CHECKSUM|STRICT_VERIFY|CATTLE_AGENT_STRICT_VERIFY)=" || true' \
    && pass "registration applied with the public certificate; Rancher → Cluster Management: ${CLUSTER_NAME} turns Active within 1-3 min" \
    || fail "registration failed on ${VM} (agent logs: sudo k3s kubectl -n cattle-system logs deploy/cattle-cluster-agent)"
  info "next: probe (baseline with Rancher up), then rancher-stop, probe again, rancher-start"
}

cmd_probe(){
  info "on ${VM}, with its own kubeconfig, Rancher $( [ "$(rancher_code)" = 200 ] && echo up || echo DOWN ), Bangkok $(bkk_now)"
  ssh_run 'echo == nodes; sudo k3s kubectl get nodes; echo == rancher agent pods; sudo k3s kubectl -n cattle-system get pods 2>/dev/null || echo none; echo == a workload created now; sudo k3s kubectl create namespace rehearsal --dry-run=client -o yaml | sudo k3s kubectl apply -f -; sudo k3s kubectl -n rehearsal create deployment rehearsal-nginx --image=nginx:1.27-alpine --dry-run=client -o yaml | sudo k3s kubectl apply -f -; sudo k3s kubectl -n rehearsal rollout restart deploy/rehearsal-nginx >/dev/null 2>&1; sudo k3s kubectl -n rehearsal rollout status deploy/rehearsal-nginx --timeout=180s; sudo k3s kubectl -n rehearsal get pods -o wide' \
    && pass "the cluster schedules and runs new work on its own" || fail "probe failed"
}

cmd_rancher_stop(){
  local st; st="$(vm_status "${RANCHER_VM}")"
  [ "${st}" = "RUNNING" ] || { warn "${RANCHER_VM} is ${st:-absent}; nothing to stop"; return 0; }
  gcloud compute instances stop "${RANCHER_VM}" --zone "${ZONE}" --project "${PROJECT}" \
    && pass "${RANCHER_VM} stopped at $(bkk_now) Bangkok — Rancher is off; next: probe, status, then rancher-start" \
    || fail "stop failed"
}

rancher_machine_type(){ gcloud compute instances describe "${RANCHER_VM}" --zone "${ZONE}" --project "${PROJECT}" --format='value(machineType.basename())' 2>/dev/null | tr -d '\r'; }
try_start(){  # one start attempt; returns 0 started, 2 no capacity, 1 other error (message in START_OUT)
  if START_OUT="$(gcloud compute instances start "${RANCHER_VM}" --zone "${ZONE}" --project "${PROJECT}" 2>&1)"; then return 0; fi
  printf '%s' "${START_OUT}" | grep -q 'ZONE_RESOURCE_POOL_EXHAUSTED' && return 2
  return 1
}

cmd_rancher_machine_type(){
  local want="${1:-}" st cur
  [ -n "${want}" ] || { fail "usage: rancher-machine-type <machine-type>   (e.g. ${DEFAULT_MACHINE_TYPE} to set it back)"; return 1; }
  st="$(vm_status "${RANCHER_VM}")"; cur="$(rancher_machine_type)"
  [ "${st}" = "TERMINATED" ] || { fail "${RANCHER_VM} is ${st:-absent}; the machine type can only change while it is TERMINATED"; return 1; }
  [ "${cur}" != "${want}" ] || { pass "${RANCHER_VM} is already ${want}"; return 0; }
  gcloud compute instances set-machine-type "${RANCHER_VM}" --zone "${ZONE}" --project "${PROJECT}" --machine-type "${want}" >/dev/null \
    && pass "${RANCHER_VM}: ${cur} -> ${want} (disk and data untouched)" || { fail "set-machine-type failed"; return 1; }
  [ "${want}" = "${DEFAULT_MACHINE_TYPE}" ] && info "matches the Terraform default again: terraform plan should say No changes" \
    || info "Terraform now sees a drift (machine_type): set it back with rancher-machine-type ${DEFAULT_MACHINE_TYPE} while the VM is stopped, or change machine_type in terraform/variables.tf"
}

wait_for_rancher(){
  local deadline; deadline=$(( $(date +%s) + 600 ))
  info "waiting for ${RANCHER_URL}/healthz (up to 10 min)"
  until [ "$(rancher_code)" = "200" ]; do
    [ "$(date +%s)" -ge "${deadline}" ] && return 1
    sleep 15
  done
  bash "${HEALTH}" "${RANCHER_URL}" | tail -n 3 | sed 's/^/  /'
}

cmd_rancher_start(){
  # rancher-start [--force] [--retry [minutes]] [--machine-type <type> | --any-type]
  local mode="" minutes=20 want="" anytype=0 a
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "${a}" in
      --force) mode="--force" ;;
      --retry) mode="--retry"; case "${1:-}" in ''|-*) ;; *) minutes="$1"; shift ;; esac ;;
      --machine-type) want="${1:?--machine-type needs a value}"; shift ;;
      --any-type) anytype=1 ;;
      '') ;;
      *) fail "unknown option ${a}"; return 1 ;;
    esac
  done
  if in_stop_window && [ "${mode}" != "--force" ]; then
    fail "Bangkok $(bkk_now): the schedule stops ${RANCHER_VM} at 18:30 (up to 15 min late); start it after 18:45, or --force"
    return 1
  fi
  local st cur orig deadline rc t
  st="$(vm_status "${RANCHER_VM}")"
  if [ "${st}" = "RUNNING" ]; then
    warn "${RANCHER_VM} already RUNNING ($(rancher_machine_type))"
  else
    [ -z "${want}" ] || { cmd_rancher_machine_type "${want}" || return 1; }
    cur="$(rancher_machine_type)"; orig="${cur}"
    deadline=$(( $(date +%s) + minutes * 60 ))
    while :; do
      try_start; rc=$?
      if [ "${rc}" = 0 ]; then
        pass "${RANCHER_VM} started at $(bkk_now) Bangkok as ${cur}"
        break
      elif [ "${rc}" = 2 ]; then
        if [ "${anytype}" = 1 ]; then
          local next="" seen=0
          for t in ${RANCHER_MACHINE_CANDIDATES:-n2-standard-4 n2d-standard-4 t2d-standard-4 n1-standard-4 c3-standard-4}; do
            if [ "${seen}" = 1 ] && [ "${t}" != "${orig}" ]; then next="${t}"; break; fi
            [ "${t}" = "${cur}" ] && seen=1
          done
          if [ "${seen}" = 0 ]; then for t in ${RANCHER_MACHINE_CANDIDATES:-n2-standard-4 n2d-standard-4 t2d-standard-4 n1-standard-4 c3-standard-4}; do [ "${t}" != "${orig}" ] && { next="${t}"; break; }; done; fi
          if [ -n "${next}" ]; then
            warn "no ${cur} capacity in ${ZONE}; trying ${next}"
            gcloud compute instances set-machine-type "${RANCHER_VM}" --zone "${ZONE}" --project "${PROJECT}" --machine-type "${next}" >/dev/null || { fail "set-machine-type ${next} failed"; return 1; }
            cur="${next}"
            continue
          fi
          warn "no capacity for any candidate type; restoring ${orig}"
          gcloud compute instances set-machine-type "${RANCHER_VM}" --zone "${ZONE}" --project "${PROJECT}" --machine-type "${orig}" >/dev/null || true
          cur="${orig}"
          [ "${mode}" = "--retry" ] || { fail "nothing started; nothing changed"; return 1; }
        fi
        if [ "${mode}" != "--retry" ]; then
          fail "no capacity for ${cur} in ${ZONE} right now (ZONE_RESOURCE_POOL_EXHAUSTED); nothing changed"
          info "options: rancher-start --retry [minutes]   or   rancher-start --any-type   (other machine families, same disk)"
          return 1
        fi
        if [ "$(date +%s)" -ge "${deadline}" ]; then
          fail "still no capacity in ${ZONE} after ${minutes} min — try --any-type, try later, or let the 08:30 schedule try (it does not retry by itself)"
          return 1
        fi
        warn "no capacity in ${ZONE} for ${cur} at $(bkk_now); retrying in 60 s (until ${minutes} min are up)"
        sleep 60
      else
        printf '%s\n' "${START_OUT}" | tr -d '\r' | tail -n 4 | sed 's/^/    /'
        fail "start failed"
        return 1
      fi
    done
    [ "${cur}" = "${DEFAULT_MACHINE_TYPE}" ] || warn "running as ${cur}, not the Terraform default ${DEFAULT_MACHINE_TYPE}: set it back later with rancher-machine-type (VM stopped), or change machine_type in terraform/variables.tf; until then terraform plan shows one change"
  fi
  wait_for_rancher || { fail "Rancher did not come back within 10 min"; return 1; }
  info "next: status (the ${CLUSTER_NAME} cluster returns to Ready by itself within 1-3 min); then delete, forget, verify-clean"
}

cmd_delete(){
  local st z; st="$(tw_status)"; z="$(tw_zone)"
  if [ -n "${st}" ]; then
    gcloud compute instances delete "${VM}" --zone "${z}" --project "${PROJECT}" --quiet \
      && pass "${VM} deleted" || { fail "delete failed"; return 1; }
  else
    warn "${VM} does not exist"
  fi
  [ -f "${IMPORT_FILE}" ] && rm -f "${IMPORT_FILE}" && info "removed ${IMPORT_FILE#"${KO_ROOT}"/}"
  info "next: forget (removes ${CLUSTER_NAME} from Rancher), then verify-clean"
}

cmd_forget(){
  [ "$(rancher_code)" = "200" ] || { fail "Rancher does not answer at ${RANCHER_URL}"; return 1; }
  # Rancher's objects carry the generated id (c-xxxxx), not the display name: the provisioning
  # cluster in fleet-default and the management cluster share that id for an imported cluster.
  local id
  id="$(rssh_run "sudo k3s kubectl get clusters.management.cattle.io -o jsonpath='{.items[?(@.spec.displayName==\"${CLUSTER_NAME}\")].metadata.name}'" | tail -n1 | tr -d ' ')"
  if [ -z "${id}" ]; then
    pass "${CLUSTER_NAME} is not listed in Rancher (nothing to forget)"; return 0
  fi
  info "${CLUSTER_NAME} is cluster ${id}; deleting its provisioning object (what the UI's Delete does)"
  rssh_run "sudo k3s kubectl -n fleet-default delete clusters.provisioning.cattle.io ${id} --ignore-not-found --timeout=120s" | sed 's/^/  /'
  local i
  for i in $(seq 1 30); do
    if ! rssh_run "sudo k3s kubectl get clusters.management.cattle.io -o jsonpath='{.items[*].metadata.name}'" | tr ' ' '\n' | grep -qx "${id}"; then
      pass "${CLUSTER_NAME} (${id}) is gone from Rancher"; return 0
    fi
    [ "${i}" = 6 ] && info "still removing (finalizers run while the downstream API is unreachable); waiting up to 5 min"
    sleep 10
  done
  fail "${CLUSTER_NAME} (${id}) still listed in Rancher after 5 min (Cluster Management in the UI)"
}

cmd_verify_clean(){
  local st code n
  st="$(tw_status)"
  [ -z "${st}" ] && pass "${VM} is gone" || fail "${VM} still exists (${st}) — run: delete"
  st="$(vm_status "${RANCHER_VM}")"
  [ "${st}" = "RUNNING" ] && pass "${RANCHER_VM} RUNNING" || warn "${RANCHER_VM} is ${st:-absent} (fine outside office hours)"
  code="$(rancher_code)"
  if [ "${code}" = "200" ]; then
    n="$(cacerts_bytes)"
    [ "${n:-0}" = "0" ] && pass "cacerts setting is empty" || fail "cacerts is set (${n} bytes): unexpected with a public certificate"
    if rssh_run "sudo k3s kubectl get clusters.management.cattle.io -o jsonpath='{.items[*].spec.displayName}'" | tr ' ' '\n' | grep -qx "${CLUSTER_NAME}"; then
      fail "${CLUSTER_NAME} still listed in Rancher — run: forget"
    else
      pass "${CLUSTER_NAME} not listed in Rancher"
    fi
  else
    warn "Rancher not reachable (${code:-no answer}): cacerts and cluster list not checked"
  fi
  [ -f "${IMPORT_FILE}" ] && warn "${IMPORT_FILE#"${KO_ROOT}"/} still present — delete it" || pass "no registration command kept locally"
  echo
  [ "${FAILED}" = 0 ] && echo "REHEARSAL CLEAN" || echo "REHEARSAL NOT CLEAN"
  return "${FAILED}"
}

usage(){ awk 'NR>1 && /^# =+$/ {c++; if (c==3) exit} NR>1 {print}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

case "${1:-help}" in
  create)        cmd_create ;;
  wait)          cmd_wait ;;
  status)        cmd_status ;;
  ssh-check)     cmd_ssh_check ;;
  import)        cmd_import ;;
  probe)         cmd_probe ;;
  rancher-stop)  cmd_rancher_stop ;;
  rancher-start) shift; cmd_rancher_start "$@" ;;
  rancher-machine-type) cmd_rancher_machine_type "${2:-}" ;;
  delete)        cmd_delete ;;
  forget)        cmd_forget ;;
  verify-clean)  cmd_verify_clean ;;
  help|-h|--help) usage ;;
  *) echo "unknown sub-command: $1"; usage; exit 2 ;;
esac
