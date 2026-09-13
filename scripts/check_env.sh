#!/usr/bin/env bash
# ==============================================================================
# DPI Center — Environment Configuration Validator (.env)
# ==============================================================================
# Purpose:
#   Validates the root .env configuration before running bootstrap or Terraform.
#   Performs static syntax/format checks and optional live GCP pre-flight checks.
#
# Usage:
#   ./scripts/check_env.sh [OPTIONS] [ENV_FILE_PATH]
#
# Options:
#   -h, --help        Show help and exit
#   -e, --env <path>  Explicit path to .env file
#   --skip-gcp        Skip live GCP API pre-flight checks (static syntax only)
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_RESET="\033[0m"

# Find repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_ENV_FILE="${REPO_ROOT}/.env"

ENV_FILE="${DEFAULT_ENV_FILE}"
SKIP_GCP=false
ERRORS=0
WARNINGS=0

print_help() {
  cat <<'EOF'
Usage:
  ./scripts/check_env.sh [OPTIONS] [ENV_FILE_PATH]

Options:
  -h, --help        Show this help message and exit.
  -e, --env <path>  Path to an alternate .env configuration file.
  --skip-gcp        Skip live GCP API checks (static syntax validation only).

Examples:
  ./scripts/check_env.sh
  ./scripts/check_env.sh --skip-gcp
  ./scripts/check_env.sh -e /custom/path/.env

Configuration Parameters in .env:
  DOMAIN_NAME          [Required] GCP Folder name, subdomain, and project prefix (<domain>-mgmt)
  BILLING_ACCOUNT_ID   [Required] GCP Billing Account ID (e.g. '01XXXX-XXXXXX-XXXXXX')
  ORGANIZATION_ID      [Optional] Defaults to '350922776586' (dpi.ait.ac.th)
  PARENT_DOMAIN        [Optional] Defaults to 'dpi.ait.ac.th'
  REGION               [Optional] Defaults to 'asia-southeast1' (Singapore)
  FOLDER_ADMINS        [Optional] Comma-separated list of admin emails
  FOLDER_MEMBERS       [Optional] Comma-separated list of viewer emails
EOF
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    -e|--env)
      if [[ -n "${2:-}" ]]; then
        ENV_FILE="$2"
        shift 2
      else
        echo -e "${COLOR_RED}❌ ERROR: --env requires a path argument.${COLOR_RESET}"
        exit 1
      fi
      ;;
    --skip-gcp)
      SKIP_GCP=true
      shift
      ;;
    *)
      ENV_FILE="$1"
      shift
      ;;
  esac
done

echo "================================================================="
echo " 🔍 DPI Center — Environment Configuration Validator"
echo "================================================================="
echo " Target File: ${ENV_FILE}"
echo "================================================================="

# --- 1. Check File Existence ---
if [[ ! -f "${ENV_FILE}" ]]; then
  echo -e "${COLOR_RED}[FAIL] Configuration file not found at: ${ENV_FILE}${COLOR_RESET}"
  echo ""
  echo "👉 Quick Setup:"
  echo "   cp .env.example .env"
  echo "   nano .env"
  echo "   ./scripts/check_env.sh"
  exit 1
fi

# Load variables
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

log_ok() {
  local key="$1"
  local val="$2"
  printf " ${COLOR_GREEN}[OK]${COLOR_RESET}   %-22s : %s\n" "${key}" "${val}"
}

log_fail() {
  local key="$1"
  local reason="$2"
  printf " ${COLOR_RED}[FAIL]${COLOR_RESET} %-22s : %s\n" "${key}" "${reason}"
  ERRORS=$((ERRORS + 1))
}

log_warn() {
  local key="$1"
  local reason="$2"
  printf " ${COLOR_YELLOW}[WARN]${COLOR_RESET} %-22s : %s\n" "${key}" "${reason}"
  WARNINGS=$((WARNINGS + 1))
}

echo ""
echo "--- [1/2] Static Configuration Checks ---"

# --- 2. Check DOMAIN_NAME ---
DOMAIN_NAME="${DOMAIN_NAME:-}"
if [[ -z "${DOMAIN_NAME}" ]]; then
  log_fail "DOMAIN_NAME" "Variable is empty or unset."
elif [[ "${DOMAIN_NAME}" == "example-domain" ]]; then
  log_fail "DOMAIN_NAME" "Still set to placeholder 'example-domain'. Set to real grant slug (e.g. 'mosip-asia')."
elif [[ ! "${DOMAIN_NAME}" =~ ^[a-z0-9-]+$ ]]; then
  log_fail "DOMAIN_NAME" "Must contain only lowercase letters, numbers, and hyphens."
elif [[ ${#DOMAIN_NAME} -gt 25 ]]; then
  log_fail "DOMAIN_NAME" "Too long (${#DOMAIN_NAME} chars, max 25 chars because project ID suffix adds '-mgmt')."
else
  log_ok "DOMAIN_NAME" "${DOMAIN_NAME} (mgmt project: ${DOMAIN_NAME}-mgmt)"
fi

# --- 3. Check BILLING_ACCOUNT_ID ---
BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID:-}"
if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
  log_fail "BILLING_ACCOUNT_ID" "Variable is empty or unset."
elif [[ "${BILLING_ACCOUNT_ID}" =~ ^01XXXX || "${BILLING_ACCOUNT_ID}" =~ XXXX ]]; then
  log_fail "BILLING_ACCOUNT_ID" "Still set to placeholder '${BILLING_ACCOUNT_ID}'. Enter real ID from GCP Console."
elif [[ ! "${BILLING_ACCOUNT_ID}" =~ ^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$ ]]; then
  log_fail "BILLING_ACCOUNT_ID" "Invalid format '${BILLING_ACCOUNT_ID}'. Must be XXXXXX-XXXXXX-XXXXXX."
else
  # Mask for display
  MASKED_BILLING="${BILLING_ACCOUNT_ID:0:6}-XXXXXX-${BILLING_ACCOUNT_ID:15:6}"
  log_ok "BILLING_ACCOUNT_ID" "${MASKED_BILLING} (Valid GCP format)"
fi

# --- 4. Check ORGANIZATION_ID ---
ORGANIZATION_ID="${ORGANIZATION_ID:-350922776586}"
if [[ ! "${ORGANIZATION_ID}" =~ ^[0-9]+$ ]]; then
  log_fail "ORGANIZATION_ID" "Must be numeric digits (e.g. 350922776586)."
else
  log_ok "ORGANIZATION_ID" "${ORGANIZATION_ID}"
fi

# --- 5. Check PARENT_DOMAIN ---
PARENT_DOMAIN="${PARENT_DOMAIN:-dpi.ait.ac.th}"
if [[ ! "${PARENT_DOMAIN}" =~ ^[a-z0-9.-]+$ ]]; then
  log_fail "PARENT_DOMAIN" "Invalid domain format."
else
  log_ok "PARENT_DOMAIN" "${PARENT_DOMAIN}"
fi

# --- 6. Check REGION ---
REGION="${REGION:-asia-southeast1}"
if [[ ! "${REGION}" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
  log_fail "REGION" "Invalid region format '${REGION}' (e.g. asia-southeast1)."
else
  log_ok "REGION" "${REGION} (Singapore)"
fi

# --- 7. Check FOLDER_ADMINS ---
FOLDER_ADMINS="${FOLDER_ADMINS:-}"
if [[ -z "${FOLDER_ADMINS}" ]]; then
  log_warn "FOLDER_ADMINS" "No admins specified. Defaulting to Org Admins."
else
  INVALID_EMAILS=0
  IFS=',' read -ra EMAILS <<< "${FOLDER_ADMINS}"
  for email in "${EMAILS[@]}"; do
    clean_email=$(echo "${email}" | xargs)
    if [[ ! "${clean_email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      log_fail "FOLDER_ADMINS" "Invalid email format: '${clean_email}'"
      INVALID_EMAILS=1
    fi
  done
  if [[ ${INVALID_EMAILS} -eq 0 ]]; then
    log_ok "FOLDER_ADMINS" "${FOLDER_ADMINS}"
  fi
fi

echo ""
echo "--- [2/2] Live Google Cloud IAM & Permission Readiness Checks ---"

if [[ "${SKIP_GCP}" == "true" ]]; then
  echo -e " ${COLOR_YELLOW}[SKIP]${COLOR_RESET} Skipping GCP API checks (--skip-gcp requested)."
elif ! command -v gcloud >/dev/null 2>&1; then
  log_warn "gcloud CLI" "gcloud command not found on PATH. Skipping live checks."
else
  export CLOUDSDK_METRICS_ENVIRONMENT="${CLOUDSDK_METRICS_ENVIRONMENT:-datacloud.antigravity}"
  ACTIVE_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)
  if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
    log_fail "gcloud Auth" "No active account found. Run 'gcloud auth login' first."
  else
    log_ok "gcloud Auth" "Authenticated as ${ACTIVE_ACCOUNT}"

    echo ""
    echo " Verifying required IAM roles for ${ACTIVE_ACCOUNT}..."
    echo " -----------------------------------------------------------------"

    # Check 1: Organization Access (organizationViewer / organizationAdmin)
    if gcloud organizations describe "${ORGANIZATION_ID}" >/dev/null 2>&1; then
      log_ok "1. Org Access" "Verified access to Organization ${ORGANIZATION_ID}"
    else
      log_fail "1. Org Access" "Cannot describe Org ${ORGANIZATION_ID}. Need 'roles/resourcemanager.organizationViewer' or 'organizationAdmin'."
    fi

    # Check 2: Folder Management / Creator (folderCreator / organizationAdmin)
    if gcloud resource-manager folders list --organization="${ORGANIZATION_ID}" --limit=1 >/dev/null 2>&1; then
      log_ok "2. Folder Creator" "Verified permission to list/manage folders in Org ${ORGANIZATION_ID}"
    else
      log_fail "2. Folder Creator" "Cannot list/create folders in Org ${ORGANIZATION_ID}. Need 'roles/resourcemanager.folderCreator' or 'organizationAdmin'."
    fi

    # Check 3: Project Creation (projectCreator / organizationAdmin)
    ORG_ROLES=$(gcloud organizations get-iam-policy "${ORGANIZATION_ID}" \
      --flatten="bindings[].members" \
      --filter="bindings.members:user:${ACTIVE_ACCOUNT}" \
      --format="value(bindings.role)" 2>/dev/null || true)

    if echo "${ORG_ROLES}" | grep -qE "roles/resourcemanager\.organizationAdmin|roles/resourcemanager\.projectCreator"; then
      log_ok "3. Project Creator" "Verified 'projectCreator' or 'organizationAdmin' at Org root"
    else
      if [[ -n "${ORG_ROLES}" ]]; then
        log_fail "3. Project Creator" "Missing 'roles/resourcemanager.projectCreator' or 'organizationAdmin' at Org root."
      else
        log_warn "3. Project Creator" "Cannot inspect Org IAM policy. Verify '${ACTIVE_ACCOUNT}' has 'roles/resourcemanager.projectCreator'."
      fi
    fi

    # Check 4: Billing Account Status (Active & Open)
    BILLING_OPEN=false
    if [[ ! "${BILLING_ACCOUNT_ID}" =~ XXXX && -n "${BILLING_ACCOUNT_ID}" ]]; then
      IS_OPEN=$(gcloud billing accounts describe "${BILLING_ACCOUNT_ID}" --format="value(open)" 2>/dev/null || true)
      if [[ "${IS_OPEN}" == "True" ]]; then
        BILLING_OPEN=true
        log_ok "4. Billing Status" "Billing Account ${MASKED_BILLING} is active and OPEN"
      else
        log_fail "4. Billing Status" "Billing Account ${MASKED_BILLING} not found or status is not OPEN."
      fi
    fi

    # Check 5: Billing Project Linking Permission (billing.user / billing.admin)
    if [[ "${BILLING_OPEN}" == "true" ]]; then
      if gcloud billing projects list --billing-account="${BILLING_ACCOUNT_ID}" --limit=1 >/dev/null 2>&1; then
        log_ok "5. Billing Linker" "Verified permission to link projects to ${MASKED_BILLING} (Role: billing.user / billing.admin)"
      else
        log_fail "5. Billing Linker" "Missing permission to link projects to ${MASKED_BILLING}. Need 'roles/billing.user' or 'roles/billing.admin' on this billing account."
      fi
    fi
  fi
fi

echo ""
echo "================================================================="
if [[ ${ERRORS} -eq 0 ]]; then
  echo -e "${COLOR_GREEN} ✅ All configuration & IAM readiness checks PASSED! (0 errors, ${WARNINGS} warnings)${COLOR_RESET}"
  echo " You are ready to proceed with:"
  echo "   ./scripts/bootstrap_domain.sh --plan"
  echo "================================================================="
  exit 0
else
  echo -e "${COLOR_RED} ❌ Readiness check FAILED with ${ERRORS} error(s) and ${WARNINGS} warning(s).${COLOR_RESET}"
  echo " Please resolve the reported permission/configuration errors before continuing."
  echo ""
  echo " 💡 Quick Remediation Guide (Run as admin@dpi.ait.ac.th if roles are missing):"
  echo "    1. To grant Organization & Folder admin rights:"
  echo "       gcloud organizations add-iam-policy-binding ${ORGANIZATION_ID} \\"
  echo "         --member=\"user:${ACTIVE_ACCOUNT:-<your-email>}\" \\"
  echo "         --role=\"roles/resourcemanager.organizationAdmin\""
  echo ""
  echo "    2. To grant Billing linking rights:"
  echo "       In GCP Console -> Billing -> Select '${MASKED_BILLING}' -> Account Management (or Permissions panel)"
  echo "       Add '${ACTIVE_ACCOUNT:-<your-email>}' with role 'Billing Account User' (roles/billing.user)."
  echo "================================================================="
  exit 1
fi
