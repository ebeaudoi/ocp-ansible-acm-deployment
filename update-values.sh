#!/bin/bash
##############################################################################
# update-values.sh — patch kustomize overlay values for RHACM and GitOps
#
# This script ONLY patches overlay kustomization.yaml files.
# It does NOT deploy anything. Deploy with:  ansible-playbook deploy.yaml
#
# HOW TO USE
#   1. Edit the VARIABLES sections below (one section per project).
#   2. Set UPDATE_*=true for the projects/overlays you want to refresh.
#   3. Run from the repo root:
#        ./update-values.sh
#
# Backups of each touched kustomization.yaml are written next to the file
# (suffix .YYYYMMDD-HHMM) and are gitignored under rhacm/ and gitops/.
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

###############################################################################
# TOGGLE — which projects to update (true / false)
# These UPDATE_* flags only control this script — not deploy.yaml.
# Deploy toggles are: -e deploy_rhacm / deploy_observability / deploy_gitops
###############################################################################
UPDATE_RHACM_CONNECTED=true
UPDATE_RHACM_AIRGAPPED=false
UPDATE_GITOPS=true

###############################################################################
# RHACM — CONNECTED overlay (operator / instance / observability)
# Paths: rhacm/*/overlays/connected/
# Connected = online cluster using redhat-operators (or similar) catalog.
# Channel default release-2.17 is intentional for connected labs; edit if needed.
###############################################################################
RHACM_CONNECTED_CHANNEL="release-2.17"          # online catalog channel
RHACM_CONNECTED_CATALOG_SOURCE="redhat-operators"  # connected CatalogSource
RHACM_CONNECTED_OSE_CLI_IMAGE="registry.redhat.io/openshift4/ose-cli-rhel9:latest"

# Observability object storage (S4 / AWS S3 / MinIO / any S3-compatible)
# Leave OBJSTORE_API_URL empty ("") to skip management-API bucket create.
RHACM_CONNECTED_OBJSTORE_NAMESPACE="s4"
RHACM_CONNECTED_OBJSTORE_SECRET_NAME="s4-credentials"
RHACM_CONNECTED_OBJSTORE_ENDPOINT="s4.s4.svc:7480"
RHACM_CONNECTED_OBJSTORE_BUCKET="acm-observability"
RHACM_CONNECTED_OBJSTORE_INSECURE="true"
RHACM_CONNECTED_OBJSTORE_API_URL="http://s4.s4.svc:5000/api"

###############################################################################
# RHACM — AIRGAPPED overlay (operator / instance / observability)
# Paths: rhacm/*/overlays/airgapped/
# Airgapped = disconnected cluster using a mirrored catalog + manual InstallPlan.
# Channel default release-2.12 is intentional for airgapped envs; edit if needed.
# (Connected vs airgapped channel skew is expected — change to match your mirror.)
###############################################################################
RHACM_AIRGAPPED_CHANNEL="release-2.12"          # mirrored catalog channel
RHACM_AIRGAPPED_CATALOG_SOURCE="ebdn-redhat-operators"  # airgapped CatalogSource
# Prefer an internal registry mirror @sha256 for disconnected clusters
RHACM_AIRGAPPED_OSE_CLI_IMAGE="registry.redhat.io/openshift4/ose-cli@sha256:3b288bdf503733042786c07ab23ba344c8ad98a38717c192584d0e1926ae9758"

# Observability object storage (same keys as connected; point at your mirror/S3)
RHACM_AIRGAPPED_OBJSTORE_NAMESPACE="s4"
RHACM_AIRGAPPED_OBJSTORE_SECRET_NAME="s4-credentials"
RHACM_AIRGAPPED_OBJSTORE_ENDPOINT="s4.s4.svc:7480"
RHACM_AIRGAPPED_OBJSTORE_BUCKET="acm-observability"
RHACM_AIRGAPPED_OBJSTORE_INSECURE="true"
RHACM_AIRGAPPED_OBJSTORE_API_URL="http://s4.s4.svc:5000/api"

###############################################################################
# GITOPS — operator overlay (connected)
# Path: gitops/operator/overlays/connected/
# Connected = online catalog (same naming as RHACM). Instance overlay is also connected/.
###############################################################################
GITOPS_SUBSCRIPTION_CHANNEL="latest"            # connected GitOps channel
GITOPS_CATALOG_SOURCE="redhat-operators"        # connected CatalogSource

###############################################################################
# Helpers (do not edit)
###############################################################################
BACKUP_SUFFIX="$(date +%Y%m%d-%HH%M)"

# YAML-quote a scalar for JSON6902 patch "value:" lines.
yaml_quote() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

replace_json6902_value() {
  local file="$1"
  local path="$2"
  local value="$3"
  python3 - "$file" "$path" "$value" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
json_path = sys.argv[2]
value = sys.argv[3]
lines = path.read_text().splitlines()
updated = False
i = 0
while i < len(lines):
    if lines[i].strip() == f"path: {json_path}":
        j = i + 1
        while j < len(lines) and lines[j].strip() == "":
            j += 1
        if j < len(lines) and lines[j].lstrip().startswith("value:"):
            indent = lines[j][: len(lines[j]) - len(lines[j].lstrip())]
            lines[j] = f"{indent}value: {value}"
            updated = True
            i = j
    i += 1
if not updated:
    raise SystemExit(f"Failed to update path {json_path} in {path}")
path.write_text("\n".join(lines) + "\n")
PY
}

mce_subscription_spec() {
  local catalog="$1"
  python3 - "${catalog}" <<'PY'
import json, sys
source = sys.argv[1]
print(json.dumps({
    "source": source,
    "config": {
        "nodeSelector": {"node-role.kubernetes.io/infra": ""},
        "tolerations": [
            {"key": "node-role.kubernetes.io/infra", "operator": "Exists", "effect": "NoSchedule"},
            {"key": "node-role.kubernetes.io/infra", "operator": "Exists", "effect": "NoExecute"},
        ],
    },
}, separators=(",", ":")))
PY
}

update_rhacm_overlay() {
  local kind="$1"   # connected | airgapped
  local channel="$2"
  local catalog="$3"
  local ose_image="$4"
  local obj_ns="$5"
  local obj_secret="$6"
  local obj_endpoint="$7"
  local obj_bucket="$8"
  local obj_insecure="$9"
  local obj_api_url="${10}"

  local op="rhacm/operator/overlays/${kind}/kustomization.yaml"
  local inst="rhacm/instance/overlays/${kind}/kustomization.yaml"
  local obs="rhacm/observability/overlays/${kind}/kustomization.yaml"

  echo ""
  echo "------------------------------------------"
  echo "[RHACM ${kind}] Updating overlays..."
  echo "  Channel:      ${channel}"
  echo "  Catalog:      ${catalog}"
  echo "  OSE CLI:      ${ose_image}"
  echo "  ObjStore NS:  ${obj_ns}"
  echo "  ObjStore Sec: ${obj_secret}"
  echo "  Endpoint:     ${obj_endpoint}"
  echo "  Bucket:       ${obj_bucket}"
  echo "  Insecure:     ${obj_insecure}"
  echo "  API URL:      ${obj_api_url:-<empty — skip bucket create>}"
  echo "------------------------------------------"

  cp "${op}"{,."${BACKUP_SUFFIX}"}
  cp "${inst}"{,."${BACKUP_SUFFIX}"}
  cp "${obs}"{,."${BACKUP_SUFFIX}"}

  replace_json6902_value "${op}" "/spec/channel" "${channel}"
  replace_json6902_value "${op}" "/spec/source" "${catalog}"
  replace_json6902_value "${obs}" "/spec/template/spec/containers/0/image" "${ose_image}"

  # ConfigMap OBJSTORE_* (quoted scalars so empty API URL is valid YAML)
  replace_json6902_value "${obs}" "/data/OBJSTORE_NAMESPACE" "$(yaml_quote "${obj_ns}")"
  replace_json6902_value "${obs}" "/data/OBJSTORE_SECRET_NAME" "$(yaml_quote "${obj_secret}")"
  replace_json6902_value "${obs}" "/data/OBJSTORE_ENDPOINT" "$(yaml_quote "${obj_endpoint}")"
  replace_json6902_value "${obs}" "/data/OBJSTORE_BUCKET" "$(yaml_quote "${obj_bucket}")"
  replace_json6902_value "${obs}" "/data/OBJSTORE_INSECURE" "$(yaml_quote "${obj_insecure}")"
  replace_json6902_value "${obs}" "/data/OBJSTORE_API_URL" "$(yaml_quote "${obj_api_url}")"

  # Credentials Role / RoleBinding must track namespace + secret name
  replace_json6902_value "${obs}" "/metadata/namespace" "$(yaml_quote "${obj_ns}")"
  replace_json6902_value "${obs}" "/rules/0/resourceNames/0" "$(yaml_quote "${obj_secret}")"

  local mce
  mce="$(mce_subscription_spec "${catalog}")"
  replace_json6902_value \
    "${inst}" \
    "/metadata/annotations/installer.open-cluster-management.io~1mce-subscription-spec" \
    "'${mce}'"

  echo "    Done."
}

update_gitops() {
  local op="gitops/operator/overlays/connected/kustomization.yaml"

  echo ""
  echo "------------------------------------------"
  echo "[GitOps] Updating operator overlay..."
  echo "  Channel: ${GITOPS_SUBSCRIPTION_CHANNEL}"
  echo "  Catalog: ${GITOPS_CATALOG_SOURCE}"
  echo "------------------------------------------"

  cp "${op}"{,."${BACKUP_SUFFIX}"}
  replace_json6902_value "${op}" "/spec/channel" "${GITOPS_SUBSCRIPTION_CHANNEL}"
  replace_json6902_value "${op}" "/spec/source" "${GITOPS_CATALOG_SOURCE}"
  echo "    Done."
}

###############################################################################
# Run
###############################################################################
echo "=========================================="
echo "update-values.sh  (patches overlays only — does not deploy)"
echo "  UPDATE_RHACM_CONNECTED = ${UPDATE_RHACM_CONNECTED}"
echo "  UPDATE_RHACM_AIRGAPPED = ${UPDATE_RHACM_AIRGAPPED}"
echo "  UPDATE_GITOPS           = ${UPDATE_GITOPS}"
echo "  Backup suffix          = .${BACKUP_SUFFIX}"
echo "=========================================="

if [[ "${UPDATE_RHACM_CONNECTED}" == "true" ]]; then
  update_rhacm_overlay connected \
    "${RHACM_CONNECTED_CHANNEL}" \
    "${RHACM_CONNECTED_CATALOG_SOURCE}" \
    "${RHACM_CONNECTED_OSE_CLI_IMAGE}" \
    "${RHACM_CONNECTED_OBJSTORE_NAMESPACE}" \
    "${RHACM_CONNECTED_OBJSTORE_SECRET_NAME}" \
    "${RHACM_CONNECTED_OBJSTORE_ENDPOINT}" \
    "${RHACM_CONNECTED_OBJSTORE_BUCKET}" \
    "${RHACM_CONNECTED_OBJSTORE_INSECURE}" \
    "${RHACM_CONNECTED_OBJSTORE_API_URL}"
fi

if [[ "${UPDATE_RHACM_AIRGAPPED}" == "true" ]]; then
  update_rhacm_overlay airgapped \
    "${RHACM_AIRGAPPED_CHANNEL}" \
    "${RHACM_AIRGAPPED_CATALOG_SOURCE}" \
    "${RHACM_AIRGAPPED_OSE_CLI_IMAGE}" \
    "${RHACM_AIRGAPPED_OBJSTORE_NAMESPACE}" \
    "${RHACM_AIRGAPPED_OBJSTORE_SECRET_NAME}" \
    "${RHACM_AIRGAPPED_OBJSTORE_ENDPOINT}" \
    "${RHACM_AIRGAPPED_OBJSTORE_BUCKET}" \
    "${RHACM_AIRGAPPED_OBJSTORE_INSECURE}" \
    "${RHACM_AIRGAPPED_OBJSTORE_API_URL}"
fi

if [[ "${UPDATE_GITOPS}" == "true" ]]; then
  update_gitops
fi

echo ""
echo "=========================================="
echo "Update completed."
echo "Deploy with:  ansible-playbook deploy.yaml"
echo "=========================================="
