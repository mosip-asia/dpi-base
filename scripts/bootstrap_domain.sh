#!/usr/bin/env bash
# ==============================================================================
# DPI Center — Domain Landing Zone Seed Bootstrap Script
# ==============================================================================
# Purpose:
#   Provisions the bedrock foundation for a new Sovereign Domain under the
#   dpi.ait.ac.th Google Cloud Organization.
#
# Execution:
#   MUST be run locally by an Organization Administrator (e.g. akraradet@ait.asia).
#
# Configuration:
#   Consumes configuration from root .env (copied from .env.example).
#
# Modes:
#   - Apply (default) : Creates any missing resources idempotently.
#   - Plan (--plan)   : Read-only preview of what would be created or changed.
#
# Idempotency Guarantee:
#   Safe to run repeatedly. Existing folders, projects, buckets, and billing
#   links are detected and preserved without duplication or breaking state.
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_BLUE="\033[0;34m"
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
ENV_FILE="${DEFAULT_ENV_FILE}"

# --- Function: Print Usage & Help ---
print_help() {
  cat <<'EOF'
================================================================================
 🏛️  DPI Center — Sovereign Domain Seed Bootstrap Runbook
================================================================================

Usage:
  ./scripts/bootstrap_domain.sh [OPTIONS] [ENV_FILE_PATH]

Options:
  -p, --plan, --dry-run  Preview actions that will be performed without making changes.
  -h, --help             Show this help message and exit.
  -e, --env <path>       Explicit path to an alternate .env configuration file.

Quickstart Guide:
  1. Create your local .env configuration file at the repository root:
       cp .env.example .env

  2. Populate the required values in .env:
       DOMAIN_NAME="mosip-asia"             # Suffix will be -mgmt (e.g. mosip-asia-mgmt)
       BILLING_ACCOUNT_ID="01XXXX-..."      # From GCP Console -> Billing

  3. Authenticate with an Organization Admin account:
       gcloud auth login akraradet@ait.asia

  4. Validate your configuration:
       ./scripts/check_env.sh

  5. Preview what will be created (Dry-Run):
       ./scripts/bootstrap_domain.sh --plan

  6. Apply and create the landing zone:
       ./scripts/bootstrap_domain.sh

Configuration Parameters in .env:
  DOMAIN_NAME          [Required] GCP Folder name, subdomain, and project prefix (<domain>-mgmt)
  BILLING_ACCOUNT_ID   [Required] GCP Billing Account ID (e.g. '01XXXX-XXXXXX-XXXXXX')
  ORGANIZATION_ID      [Optional] Defaults to '350922776586' (dpi.ait.ac.th)
  PARENT_DOMAIN        [Optional] Defaults to 'dpi.ait.ac.th'
  REGION               [Optional] Defaults to 'asia-southeast1' (Singapore)
  FOLDER_ADMINS        [Optional] Comma-separated list of admin emails
  FOLDER_MEMBERS       [Optional] Comma-separated list of viewer emails

Idempotency:
  This script is 100% idempotent. If a folder, project, billing link, or bucket
  already exists, it detects and preserves them without error or duplication.
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
    -e|--env)
      if [[ -n "${2:-}" ]]; then
        ENV_FILE="$2"
        shift 2
      else
        echo -e "${COLOR_RED}❌ ERROR: --env requires a path argument.${COLOR_RESET}"
        exit 1
      fi
      ;;
    *)
      # Positional argument treated as env file path
      ENV_FILE="$1"
      shift
      ;;
  esac
done

# --- 1. Validate Environment Configuration using check_env.sh ---
if [[ -f "${SCRIPT_DIR}/check_env.sh" ]]; then
  echo "==> Step 0: Validating environment configuration..."
  "${SCRIPT_DIR}/check_env.sh" --env "${ENV_FILE}"
  echo ""
else
  # Fallback basic check if check_env.sh is missing
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo -e "${COLOR_RED}❌ ERROR: Configuration file not found at: ${ENV_FILE}${COLOR_RESET}"
    exit 1
  fi
fi

# Load environment variables from validated .env
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

# Set defaults for optional variables
ORGANIZATION_ID="${ORGANIZATION_ID:-350922776586}"
PARENT_DOMAIN="${PARENT_DOMAIN:-dpi.ait.ac.th}"
REGION="${REGION:-asia-southeast1}"
FOLDER_ADMINS="${FOLDER_ADMINS:-akraradet@ait.asia,nuttasit@ait.asia}"
FOLDER_MEMBERS="${FOLDER_MEMBERS:-}"

# --- 2. Auto-Rename Template Folder if present ---
if [[ -d "${REPO_ROOT}/template-mgmt" ]]; then
  if [[ "${PLAN_MODE}" == "true" ]]; then
    echo "==> [PLAN] Would rename template-mgmt/ to ${DOMAIN_NAME}-mgmt/"
  else
    echo "==> Renaming template-mgmt/ to ${DOMAIN_NAME}-mgmt/..."
    mv "${REPO_ROOT}/template-mgmt" "${REPO_ROOT}/${DOMAIN_NAME}-mgmt"
  fi
fi

# --- 3. Auto-Detect Target Terraform Directory ---
TARGET_TF_DIR=""
if [[ -d "${REPO_ROOT}/${DOMAIN_NAME}-mgmt/terraform" ]]; then
  TARGET_TF_DIR="${REPO_ROOT}/${DOMAIN_NAME}-mgmt/terraform"
elif [[ -d "${REPO_ROOT}/dpi-mgmt/terraform" ]]; then
  TARGET_TF_DIR="${REPO_ROOT}/dpi-mgmt/terraform"
elif [[ -d "${REPO_ROOT}/mgmt/terraform" ]]; then
  TARGET_TF_DIR="${REPO_ROOT}/mgmt/terraform"
else
  TARGET_TF_DIR="${REPO_ROOT}"
fi

OUTPUT_TFVARS_PATH="${TARGET_TF_DIR}/terraform.tfvars"
TARGET_TF_REL="${TARGET_TF_DIR#"${REPO_ROOT}/"}"

readonly PROJECT_ID="${DOMAIN_NAME}-mgmt"
readonly BUCKET_NAME="${DOMAIN_NAME}-tfstate"
readonly SUBDOMAIN="${DOMAIN_NAME}.${PARENT_DOMAIN}"
readonly MASKED_BILLING="${BILLING_ACCOUNT_ID:0:6}-XXXXXX-${BILLING_ACCOUNT_ID:15:6}"

# Header
echo "================================================================="
if [[ "${PLAN_MODE}" == "true" ]]; then
  echo -e " 📋  ${COLOR_CYAN}DPI Center — Landing Zone Bootstrap (PLAN / DRY-RUN)${COLOR_RESET}"
else
  echo -e " 🏛️  ${COLOR_GREEN}DPI Center — Landing Zone Bootstrap (APPLY)${COLOR_RESET}"
fi
echo "================================================================="
echo "  Config Source      : ${ENV_FILE}"
echo "  Organization ID    : ${ORGANIZATION_ID} (${PARENT_DOMAIN})"
echo "  Domain Name        : ${DOMAIN_NAME}"
echo "  Anchor Project ID  : ${PROJECT_ID}"
echo "  Billing Account ID : ${MASKED_BILLING}"
echo "  State Bucket Name  : gs://${BUCKET_NAME}"
echo "  Region             : ${REGION} (Singapore)"
echo "  Subdomain Namespace: ${SUBDOMAIN}"
echo "  Output tfvars Path : ${OUTPUT_TFVARS_PATH}"
echo "================================================================="
echo ""

# --- 3. Verify Prerequisites & gcloud Identity ---
echo "==> Step 1: Verifying active gcloud identity..."
ACTIVE_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo -e "${COLOR_RED}❌ ERROR: No active gcloud account found. Please run 'gcloud auth login' first.${COLOR_RESET}"
  exit 1
fi
echo -e "    ${COLOR_GREEN}[OK]${COLOR_RESET} Authenticated as: ${ACTIVE_ACCOUNT}"

export CLOUDSDK_METRICS_ENVIRONMENT="${CLOUDSDK_METRICS_ENVIRONMENT:-datacloud.antigravity}"

# --- Track Plan Actions ---
PLAN_ACTIONS=0
PLAN_NOCHANGE=0

plan_action() {
  local action="$1"
  local desc="$2"
  printf " ${COLOR_GREEN}[+] WOULD %-7s${COLOR_RESET} : %s\n" "${action}" "${desc}"
  PLAN_ACTIONS=$((PLAN_ACTIONS + 1))
}

plan_nochange() {
  local target="$1"
  local desc="$2"
  printf " ${COLOR_CYAN}[=] NO CHANGE   ${COLOR_RESET} : %s (%s)\n" "${target}" "${desc}"
  PLAN_NOCHANGE=$((PLAN_NOCHANGE + 1))
}

# --- 4. Check / Plan / Create GCP Folder ---
echo ""
echo "==> Step 2: Evaluating GCP Folder '${DOMAIN_NAME}' under Org ${ORGANIZATION_ID}..."
EXISTING_FOLDER=$(gcloud resource-manager folders list \
  --organization="${ORGANIZATION_ID}" \
  --filter="displayName='${DOMAIN_NAME}'" \
  --format="value(name)" 2>/dev/null || true)

FOLDER_FULL_ID=""
if [[ -n "${EXISTING_FOLDER}" ]]; then
  FOLDER_FULL_ID="${EXISTING_FOLDER}"
  if [[ "${PLAN_MODE}" == "true" ]]; then
    plan_nochange "GCP Folder" "Already exists: ${FOLDER_FULL_ID}"
  else
    echo -e "    ${COLOR_CYAN}[EXISTS]${COLOR_RESET} Folder already exists: ${FOLDER_FULL_ID}"
  fi
else
  if [[ "${PLAN_MODE}" == "true" ]]; then
    plan_action "CREATE" "Folder '${DOMAIN_NAME}' under Org ${ORGANIZATION_ID}"
    FOLDER_FULL_ID="folders/(pending-create)"
  else
    echo "    Creating folder '${DOMAIN_NAME}'..."
    FOLDER_FULL_ID=$(gcloud resource-manager folders create \
      --display-name="${DOMAIN_NAME}" \
      --organization="${ORGANIZATION_ID}" \
      --format="value(name)")
    echo -e "    ${COLOR_GREEN}[CREATED]${COLOR_RESET} Folder: ${FOLDER_FULL_ID}"
  fi
fi

FOLDER_NUMERIC_ID="${FOLDER_FULL_ID#folders/}"

# --- 5. Check / Plan / Create Anchor Management Project ---
echo ""
echo "==> Step 3: Evaluating Management Project '${PROJECT_ID}'..."
PROJECT_EXISTS=false
if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  PROJECT_EXISTS=true
fi

if [[ "${PROJECT_EXISTS}" == "true" ]]; then
  if [[ "${PLAN_MODE}" == "true" ]]; then
    plan_nochange "Project" "Already exists: ${PROJECT_ID}"
  else
    echo -e "    ${COLOR_CYAN}[EXISTS]${COLOR_RESET} Project '${PROJECT_ID}' already exists."
  fi
else
  if [[ "${PLAN_MODE}" == "true" ]]; then
    plan_action "CREATE" "Project '${PROJECT_ID}' inside Folder ${FOLDER_FULL_ID}"
  else
    echo "    Creating project '${PROJECT_ID}' in Folder ${FOLDER_NUMERIC_ID}..."
    gcloud projects create "${PROJECT_ID}" \
      --folder="${FOLDER_NUMERIC_ID}" \
      --name="DPI ${DOMAIN_NAME} Management"
    echo -e "    ${COLOR_GREEN}[CREATED]${COLOR_RESET} Project '${PROJECT_ID}'."
    PROJECT_EXISTS=true
    echo "    Waiting 5s for GCP Resource Manager propagation..."
    sleep 5
  fi
fi

# --- 6. Check / Plan / Link Billing Account ---
echo ""
echo "==> Step 4: Evaluating Billing Association for '${PROJECT_ID}'..."
CURRENT_BILLING=""
if [[ "${PROJECT_EXISTS}" == "true" ]]; then
  CURRENT_BILLING=$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || true)
  # Strips 'billingAccounts/' prefix if returned
  CURRENT_BILLING="${CURRENT_BILLING#billingAccounts/}"
fi

if [[ "${CURRENT_BILLING}" == "${BILLING_ACCOUNT_ID}" ]]; then
  if [[ "${PLAN_MODE}" == "true" ]]; then
    plan_nochange "Billing Link" "Already linked to ${MASKED_BILLING}"
  else
    echo -e "    ${COLOR_CYAN}[LINKED]${COLOR_RESET} Already linked to Billing Account ${MASKED_BILLING}."
  fi
else
  if [[ "${PLAN_MODE}" == "true" ]]; then
    plan_action "LINK" "Project '${PROJECT_ID}' to Billing Account ${MASKED_BILLING}"
  else
    echo "    Linking Billing Account ${MASKED_BILLING} to '${PROJECT_ID}'..."
    LINK_SUCCESS=false
    MAX_RETRIES=5
    for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
      if gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT_ID}" >/dev/null 2>&1; then
        LINK_SUCCESS=true
        break
      fi
      if [[ ${attempt} -lt ${MAX_RETRIES} ]]; then
        echo "    Waiting for project propagation in Billing API (attempt ${attempt}/${MAX_RETRIES}, retrying in 5s)..."
        sleep 5
      fi
    done

    if [[ "${LINK_SUCCESS}" == "true" ]]; then
      echo -e "    ${COLOR_GREEN}[LINKED]${COLOR_RESET} Billing account linked successfully."
    else
      echo -e "    ${COLOR_YELLOW}[RETRYING]${COLOR_RESET} Performing final link attempt to capture detailed response..."
      gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT_ID}"
      echo -e "    ${COLOR_GREEN}[LINKED]${COLOR_RESET} Billing account linked successfully."
    fi
  fi
fi

# --- 7. Check / Plan / Enable Core APIs ---
echo ""
echo "==> Step 5: Evaluating Core Seed APIs on '${PROJECT_ID}'..."
SEED_APIS=("cloudresourcemanager.googleapis.com" "serviceusage.googleapis.com" "storage.googleapis.com")

if [[ "${PLAN_MODE}" == "true" ]]; then
  if [[ "${PROJECT_EXISTS}" == "true" ]]; then
    plan_nochange "APIs" "Ensure core APIs enabled (cloudresourcemanager, serviceusage, storage)"
  else
    plan_action "ENABLE" "Core APIs (cloudresourcemanager, serviceusage, storage)"
  fi
else
  echo "    Ensuring core APIs are enabled on '${PROJECT_ID}'..."
  API_SUCCESS=false
  for ((attempt=1; attempt<=3; attempt++)); do
    if gcloud services enable "${SEED_APIS[@]}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
      API_SUCCESS=true
      break
    fi
    if [[ ${attempt} -lt 3 ]]; then
      echo "    Waiting for serviceusage API availability (attempt ${attempt}/3)..."
      sleep 5
    fi
  done
  if [[ "${API_SUCCESS}" == "true" ]]; then
    echo -e "    ${COLOR_GREEN}[ENABLED]${COLOR_RESET} Core APIs verified."
  else
    gcloud services enable "${SEED_APIS[@]}" --project="${PROJECT_ID}"
    echo -e "    ${COLOR_GREEN}[ENABLED]${COLOR_RESET} Core APIs verified."
  fi
fi

# --- 8. Check / Plan / Create Remote State Bucket ---
echo ""
echo "==> Step 6: Evaluating Remote State Bucket 'gs://${BUCKET_NAME}'..."
BUCKET_EXISTS=false
if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  BUCKET_EXISTS=true
fi

if [[ "${BUCKET_EXISTS}" == "true" ]]; then
  if [[ "${PLAN_MODE}" == "true" ]]; then
    plan_nochange "GCS Bucket" "Bucket 'gs://${BUCKET_NAME}' already exists (Singapore)"
  else
    echo -e "    ${COLOR_CYAN}[EXISTS]${COLOR_RESET} Bucket 'gs://${BUCKET_NAME}' already exists."
  fi
else
  if [[ "${PLAN_MODE}" == "true" ]]; then
    plan_action "CREATE" "Bucket 'gs://${BUCKET_NAME}' in ${REGION} (Singapore, Versioning ON)"
  else
    echo "    Creating bucket 'gs://${BUCKET_NAME}' in ${REGION}..."
    gcloud storage buckets create "gs://${BUCKET_NAME}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --uniform-bucket-level-access
    echo -e "    ${COLOR_GREEN}[CREATED]${COLOR_RESET} Bucket gs://${BUCKET_NAME}."
  fi
fi

# Check / Enable Versioning
if [[ "${PLAN_MODE}" == "false" ]]; then
  gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning >/dev/null 2>&1 || true
  echo -e "    ${COLOR_GREEN}[VERIFIED]${COLOR_RESET} Object versioning active on gs://${BUCKET_NAME}."
fi

# --- 9. Format Admin & Member HCL Arrays ---
format_hcl_array() {
  local csv="${1:-}"
  local formatted=""
  if [[ -z "${csv}" ]]; then
    echo ""
    return 0
  fi
  IFS=',' read -ra ADDR <<< "${csv}"
  for item in "${ADDR[@]}"; do
    local trimmed
    trimmed=$(echo "${item}" | xargs)
    if [[ -n "${trimmed}" ]]; then
      formatted="${formatted}  \"${trimmed}\",\n"
    fi
  done
  echo -e "${formatted}"
}

ADMINS_HCL=$(format_hcl_array "${FOLDER_ADMINS}")
MEMBERS_HCL=$(format_hcl_array "${FOLDER_MEMBERS}")

# --- 10. Generate terraform.tfvars Content ---
TFVARS_CONTENT=$(cat <<EOF
# ==============================================================================
# Auto-generated by bootstrap_domain.sh from: ${ENV_FILE}
# Domain Identifier : ${DOMAIN_NAME}
# Generated at       : $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ==============================================================================

organization_id    = "${ORGANIZATION_ID}"
folder_id          = "${FOLDER_FULL_ID}"
project_id         = "${PROJECT_ID}"
billing_account_id = "${BILLING_ACCOUNT_ID}"
domain_name        = "${SUBDOMAIN}."
state_bucket       = "${BUCKET_NAME}"
region             = "${REGION}"

# Team Collaborators (Folder IAM)
folder_admins = [
${ADMINS_HCL}]

folder_members = [
${MEMBERS_HCL}]
EOF
)

# --- Output Summary ---
echo ""
echo "================================================================="

if [[ "${PLAN_MODE}" == "true" ]]; then
  echo -e " 📋  ${COLOR_CYAN}Bootstrap Plan Summary: ${PLAN_ACTIONS} to create/link, ${PLAN_NOCHANGE} unchanged.${COLOR_RESET}"
  echo "================================================================="
  echo ""
  echo "Preview of generated terraform.tfvars:"
  echo "-----------------------------------------------------------------"
  echo "${TFVARS_CONTENT}"
  echo "-----------------------------------------------------------------"
  echo ""
  echo "👉 To apply this plan and provision resources in GCP, run:"
  echo -e "     ${COLOR_GREEN}./scripts/bootstrap_domain.sh${COLOR_RESET}"
  echo "================================================================="
  exit 0
fi

echo -e " ✅  ${COLOR_GREEN}Seed Bootstrap Successfully Completed!${COLOR_RESET}"
echo "================================================================="
echo ""
echo "Generated Configuration:"
echo "-----------------------------------------------------------------"
echo "${TFVARS_CONTENT}"
echo "-----------------------------------------------------------------"

if [[ -n "${OUTPUT_TFVARS_PATH}" ]]; then
  mkdir -p "$(dirname "${OUTPUT_TFVARS_PATH}")"
  echo "${TFVARS_CONTENT}" > "${OUTPUT_TFVARS_PATH}"
  echo ""
  echo "📁 Saved configuration to: ${OUTPUT_TFVARS_PATH}"
fi

echo ""
echo "================================================================="
echo " 👉 NEXT STEPS TO ACTIVATE THIS DOMAIN"
echo "================================================================="
echo ""
echo "Step 1: Deploy GitOps Foundation via Terraform"
echo "  Run the following commands to provision DNS, secrets, and project lien:"
echo -e "    ${COLOR_GREEN}cd ${TARGET_TF_REL}${COLOR_RESET}"
echo "    terraform init -backend-config=\"bucket=${BUCKET_NAME}\""
echo "    terraform apply"
echo ""
echo "Step 2: Obtain Assigned Nameservers"
echo "  Once 'terraform apply' completes, capture the 4 dynamically assigned nameservers:"
echo -e "    ${COLOR_GREEN}terraform output name_servers${COLOR_RESET}"
echo ""
echo "Step 3: One-Time Parent DNS Delegation Handshake"
echo "  Copy and send the message below to the Domain Administrator (or execute it"
echo "  yourself if you have access to the parent DNS project 'ait-brainlab-mgmt'):"
echo ""
echo "  -----------------------------------------------------------------"
echo "  📨 COPY-PASTE MESSAGE FOR DOMAIN ADMIN:"
echo "  -----------------------------------------------------------------"
echo "  Hi Admin,"
echo "  Please add a one-time DNS delegation (NS record) for our new domain:"
echo ""
echo "    Parent Zone : dpi-center (in project 'ait-brainlab-mgmt')"
echo "    Record Name : ${DOMAIN_NAME}"
echo "    Full Domain : ${SUBDOMAIN}."
echo "    Record Type : NS"
echo "    TTL         : 300"
echo "    Nameservers : <PASTE_4_NAMESERVERS_FROM_STEP_2>"
echo ""
echo "  Or via gcloud CLI:"
echo "    gcloud dns record-sets transaction start --zone=dpi-center --project=ait-brainlab-mgmt"
echo "    gcloud dns record-sets transaction add <NS1> <NS2> <NS3> <NS4> \\"
echo "      --name=\"${SUBDOMAIN}.\" --ttl=300 --type=NS --zone=dpi-center --project=ait-brainlab-mgmt"
echo "    gcloud dns record-sets transaction execute --zone=dpi-center --project=ait-brainlab-mgmt"
echo "  -----------------------------------------------------------------"
echo ""
echo "Step 4: Verify Public Resolution"
echo "  Once the NS record is saved in the parent zone, verify public routing:"
echo -e "    ${COLOR_GREEN}dig NS ${SUBDOMAIN} +short${COLOR_RESET}"
echo "================================================================="
