#!/usr/bin/env bash
# ==============================================================================
# DPI Center — Domain Management Plane Scaffolding Tool
# ==============================================================================
# Purpose:
#   Scaffolds a new Sovereign Domain management directory (<domain>-mgmt/)
#   locally from the reusable 'template-mgmt/' template.
#
# Execution:
#   Can be run independently or invoked automatically by bootstrap_domain.sh.
#   Requires NO cloud credentials or network calls — 100% local workspace tool.
#
# Configuration:
#   Reads configuration from root .env or via CLI arguments.
#
# Modes:
#   - Apply (default) : Copies template-mgmt/ to <domain>-mgmt/ and renders variables.
#   - Plan (--plan)   : Preview what would be created without making changes.
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_CYAN="\033[0;36m"
readonly COLOR_RESET="\033[0m"

# Determine directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check default .env location (root first, then scripts/)
if [[ -f "${REPO_ROOT}/.env" ]]; then
  DEFAULT_ENV_FILE="${REPO_ROOT}/.env"
else
  DEFAULT_ENV_FILE="${SCRIPT_DIR}/.env"
fi

PLAN_MODE=false
FORCE_MODE=false
ENV_FILE="${DEFAULT_ENV_FILE}"
DOMAIN_OVERRIDE=""

# --- Function: Print Usage & Help ---
print_help() {
  cat <<'EOF'
================================================================================
 📁  DPI Center — Domain Management Scaffolding Tool
================================================================================

Usage:
  ./scripts/scaffold_domain.sh [OPTIONS] [DOMAIN_NAME]

Options:
  -p, --plan, --dry-run  Preview scaffolding actions without creating files.
  -f, --force            Force re-scaffolding if target directory already exists.
  -e, --env <path>       Explicit path to an alternate .env configuration file.
  -h, --help             Show this help message and exit.

Examples:
  # Scaffold using variables defined in root .env:
  ./scripts/scaffold_domain.sh

  # Scaffold a specific domain directly:
  ./scripts/scaffold_domain.sh ait-vc

  # Preview actions with dry-run:
  ./scripts/scaffold_domain.sh --plan ait-vc
================================================================================
EOF
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    -p|--plan|--dry-run)
      PLAN_MODE=true
      shift
      ;;
    -f|--force)
      FORCE_MODE=true
      shift
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
    -*)
      echo -e "${COLOR_RED}❌ ERROR: Unknown option '$1'. Use --help for usage.${COLOR_RESET}"
      exit 1
      ;;
    *)
      DOMAIN_OVERRIDE="$1"
      shift
      ;;
  esac
done

# Load environment file if it exists
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

# Override DOMAIN_NAME if passed as positional CLI argument
if [[ -n "${DOMAIN_OVERRIDE}" ]]; then
  DOMAIN_NAME="${DOMAIN_OVERRIDE}"
fi

DOMAIN_NAME="${DOMAIN_NAME:-}"
if [[ -z "${DOMAIN_NAME}" ]]; then
  echo -e "${COLOR_RED}❌ ERROR: DOMAIN_NAME is not set.${COLOR_RESET}"
  echo "👉 Provide DOMAIN_NAME via root .env or pass it as an argument:"
  echo "   ./scripts/scaffold_domain.sh <domain-name>"
  exit 1
fi

# Sanitize domain name
if [[ ! "${DOMAIN_NAME}" =~ ^[a-z0-9-]+$ ]]; then
  echo -e "${COLOR_RED}❌ ERROR: DOMAIN_NAME '${DOMAIN_NAME}' must contain only lowercase alphanumeric characters and hyphens.${COLOR_RESET}"
  exit 1
fi

if [[ ${#DOMAIN_NAME} -gt 24 ]]; then
  echo -e "${COLOR_RED}❌ ERROR: DOMAIN_NAME '${DOMAIN_NAME}' is too long (${#DOMAIN_NAME} chars, max 24 chars).${COLOR_RESET}"
  exit 1
fi

# Defaults
PARENT_DOMAIN="${PARENT_DOMAIN:-dpi.ait.ac.th}"
PARENT_SLUG="${PARENT_DOMAIN//./-}"
STATE_BUCKET="${STATE_BUCKET:-${DOMAIN_NAME}-${PARENT_SLUG}-tfstate}"
readonly BUCKET_NAME="${STATE_BUCKET}"
readonly SUBDOMAIN="${DOMAIN_NAME}.${PARENT_DOMAIN}"
readonly TEMPLATE_DIR="${REPO_ROOT}/template-mgmt"
readonly TARGET_MGMT_DIR="${REPO_ROOT}/${DOMAIN_NAME}-mgmt"
readonly TARGET_TF_DIR="${TARGET_MGMT_DIR}/terraform"

# Verify template exists
if [[ ! -d "${TEMPLATE_DIR}" ]]; then
  echo -e "${COLOR_RED}❌ ERROR: Template directory not found at: ${TEMPLATE_DIR}${COLOR_RESET}"
  exit 1
fi

# Header
echo "================================================================="
if [[ "${PLAN_MODE}" == "true" ]]; then
  echo -e " 📋  ${COLOR_CYAN}DPI Center — Domain Scaffolding (PLAN / DRY-RUN)${COLOR_RESET}"
else
  echo -e " 📁  ${COLOR_GREEN}DPI Center — Domain Scaffolding (APPLY)${COLOR_RESET}"
fi
echo "================================================================="
echo "  Source Template    : ${TEMPLATE_DIR#"${REPO_ROOT}/"}"
echo "  Target Directory   : ${TARGET_MGMT_DIR#"${REPO_ROOT}/"}"
echo "  Domain Identifier  : ${DOMAIN_NAME}"
echo "  Subdomain Namespace: ${SUBDOMAIN}"
echo "  State Bucket Name  : gs://${BUCKET_NAME}"
echo "================================================================="
echo ""

# Check if target already exists
if [[ -d "${TARGET_MGMT_DIR}" && "${FORCE_MODE}" != "true" ]]; then
  if [[ "${PLAN_MODE}" == "true" ]]; then
    echo -e " ${COLOR_CYAN}[=] NO CHANGE${COLOR_RESET}   : Directory '${TARGET_MGMT_DIR#"${REPO_ROOT}/"}' already exists."
    echo ""
    echo "Use --force if you wish to overwrite existing files."
    exit 0
  else
    echo -e "    ${COLOR_CYAN}[EXISTS]${COLOR_RESET} Management directory already exists: ${TARGET_MGMT_DIR#"${REPO_ROOT}/"}"
    echo "    Skipping scaffolding (template preserved). Use --force to overwrite."
    exit 0
  fi
fi

# Dry-run plan preview
if [[ "${PLAN_MODE}" == "true" ]]; then
  echo "Plan Actions:"
  printf " ${COLOR_GREEN}[+] WOULD COPY     ${COLOR_RESET} : %s -> %s\n" "${TEMPLATE_DIR#"${REPO_ROOT}/"}" "${TARGET_MGMT_DIR#"${REPO_ROOT}/"}"
  printf " ${COLOR_GREEN}[+] WOULD RENDER   ${COLOR_RESET} : __STATE_BUCKET__ -> %s in %s/main.tf\n" "${BUCKET_NAME}" "${TARGET_TF_DIR#"${REPO_ROOT}/"}"
  printf " ${COLOR_GREEN}[+] WOULD RENDER   ${COLOR_RESET} : __DOMAIN_NAME__ -> %s in %s/README.md\n" "${DOMAIN_NAME}" "${TARGET_MGMT_DIR#"${REPO_ROOT}/"}"
  printf " ${COLOR_GREEN}[+] WOULD RENDER   ${COLOR_RESET} : __SUBDOMAIN__ -> %s in %s/README.md\n" "${SUBDOMAIN}" "${TARGET_MGMT_DIR#"${REPO_ROOT}/"}"
  echo ""
  echo "👉 To execute this scaffolding plan, run:"
  echo -e "     ${COLOR_GREEN}./scripts/scaffold_domain.sh ${DOMAIN_NAME}${COLOR_RESET}"
  echo "================================================================="
  exit 0
fi

# Execute apply
echo "==> Scaffolding '${TARGET_MGMT_DIR#"${REPO_ROOT}/"}' from 'template-mgmt/'..."
cp -R "${TEMPLATE_DIR}" "${TARGET_MGMT_DIR}"

# Replace placeholders in copied files
if [[ -f "${TARGET_TF_DIR}/main.tf" ]]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|__STATE_BUCKET__|${BUCKET_NAME}|g" "${TARGET_TF_DIR}/main.tf"
  else
    sed -i "s|__STATE_BUCKET__|${BUCKET_NAME}|g" "${TARGET_TF_DIR}/main.tf"
  fi
fi

if [[ -f "${TARGET_MGMT_DIR}/README.md" ]]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|__DOMAIN_NAME__|${DOMAIN_NAME}|g" "${TARGET_MGMT_DIR}/README.md"
    sed -i '' "s|__STATE_BUCKET__|${BUCKET_NAME}|g" "${TARGET_MGMT_DIR}/README.md"
    sed -i '' "s|__SUBDOMAIN__|${SUBDOMAIN}|g" "${TARGET_MGMT_DIR}/README.md"
  else
    sed -i "s|__DOMAIN_NAME__|${DOMAIN_NAME}|g" "${TARGET_MGMT_DIR}/README.md"
    sed -i "s|__STATE_BUCKET__|${BUCKET_NAME}|g" "${TARGET_MGMT_DIR}/README.md"
    sed -i "s|__SUBDOMAIN__|${SUBDOMAIN}|g" "${TARGET_MGMT_DIR}/README.md"
  fi
fi

echo -e "    ${COLOR_GREEN}[SCAFFOLDED]${COLOR_RESET} Created ${TARGET_MGMT_DIR#"${REPO_ROOT}/"} successfully."
echo -e "    ${COLOR_GREEN}[PRESERVED]${COLOR_RESET} Source 'template-mgmt/' remains intact for future domains."
echo ""
echo "================================================================="
echo -e " ✅  ${COLOR_GREEN}Scaffolding Completed Successfully!${COLOR_RESET}"
echo "================================================================="
echo "  Files Created:"
echo "    - ${TARGET_MGMT_DIR#"${REPO_ROOT}/"}/README.md"
echo "    - ${TARGET_MGMT_DIR#"${REPO_ROOT}/"}/oauth_setup.md"
echo "    - ${TARGET_TF_DIR#"${REPO_ROOT}/"}/main.tf (state bucket: gs://${BUCKET_NAME})"
echo "    - ${TARGET_TF_DIR#"${REPO_ROOT}/"}/dns.tf"
echo "    - ${TARGET_TF_DIR#"${REPO_ROOT}/"}/iam.tf"
echo "    - ${TARGET_TF_DIR#"${REPO_ROOT}/"}/secrets.tf"
echo "    - ${TARGET_TF_DIR#"${REPO_ROOT}/"}/variables.tf"
echo "    - ${TARGET_TF_DIR#"${REPO_ROOT}/"}/outputs.tf"
echo "    - ${TARGET_TF_DIR#"${REPO_ROOT}/"}/prj-workload.tf.example"
echo "================================================================="
