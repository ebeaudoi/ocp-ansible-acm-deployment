#!/bin/bash
####################################################
# RHACM values update — connected (non-air-gapped) #
# Updates overlays/connected kustomization values  #
####################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

################################
# IMPORTANT                    #
# Update the variables below   #
################################
RHACM_SUBSCRIPTION_CHANNEL="release-2.17"
# Default public Red Hat catalog on connected clusters
RHACM_CATALOG_SOURCE="redhat-operators"
# Public registry image (pin a tag or digest if you prefer)
RHACM_OSE_CLI_IMAGE="registry.redhat.io/openshift4/ose-cli-rhel9:latest"

OPERATOR_OVERLAY="operator/overlays/connected/kustomization.yaml"
INSTANCE_OVERLAY="instance/overlays/connected/kustomization.yaml"
OBSERVABILITY_OVERLAY="observability/overlays/connected/kustomization.yaml"

################################
# Backup the files             #
################################
BACKUP_SUFFIX="$(date +%Y%m%d-%HH%M)"
cp "${OPERATOR_OVERLAY}"{,."${BACKUP_SUFFIX}"}
cp "${OBSERVABILITY_OVERLAY}"{,."${BACKUP_SUFFIX}"}
cp "${INSTANCE_OVERLAY}"{,."${BACKUP_SUFFIX}"}

################################
# Display configuration         #
################################
echo "=========================================="
echo "RHACM Connected Cluster Configuration"
echo "=========================================="
echo "  Overlay:              connected"
echo "  Subscription Channel: ${RHACM_SUBSCRIPTION_CHANNEL}"
echo "  Catalog Source:       ${RHACM_CATALOG_SOURCE}"
echo "  OSE CLI Image:        ${RHACM_OSE_CLI_IMAGE}"
echo "  InstallPlanApproval:  Automatic (base default)"
echo "=========================================="
echo ""

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

################################
# Update Operator Overlay       #
################################
echo "[RHACM Operator] Updating connected operator overlay..."
echo "  File: ${OPERATOR_OVERLAY}"
replace_json6902_value "${OPERATOR_OVERLAY}" "/spec/channel" "${RHACM_SUBSCRIPTION_CHANNEL}"
echo "    Updated subscription channel: ${RHACM_SUBSCRIPTION_CHANNEL}"
replace_json6902_value "${OPERATOR_OVERLAY}" "/spec/source" "${RHACM_CATALOG_SOURCE}"
echo "    Updated catalog source: ${RHACM_CATALOG_SOURCE}"
echo ""

################################
# Update Observability Overlay  #
################################
echo "[RHACM Observability] Updating connected observability overlay..."
echo "  File: ${OBSERVABILITY_OVERLAY}"
replace_json6902_value \
  "${OBSERVABILITY_OVERLAY}" \
  "/spec/template/spec/containers/0/image" \
  "${RHACM_OSE_CLI_IMAGE}"
echo "    Updated OSE CLI image"
echo ""

################################
# Update Instance Overlay       #
################################
echo "[RHACM Instance] Updating connected MultiClusterHub overlay..."
echo "  File: ${INSTANCE_OVERLAY}"
MCE_VALUE=$(python3 - "${RHACM_CATALOG_SOURCE}" <<'PY'
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
)
replace_json6902_value \
  "${INSTANCE_OVERLAY}" \
  "/metadata/annotations/installer.open-cluster-management.io~1mce-subscription-spec" \
  "'${MCE_VALUE}'"
echo "    Updated MCE subscription spec with catalog: ${RHACM_CATALOG_SOURCE} (infra config preserved)"
echo ""

echo "=========================================="
echo "RHACM connected update completed successfully"
echo "=========================================="
echo "Backups written with suffix: .${BACKUP_SUFFIX}"
echo "(Ignored by rhacm/.gitignore)"
echo ""
echo "Deploy with:"
echo "  oc apply -k operator/overlays/connected/"
echo "  oc apply -k instance/overlays/connected/"
echo "  oc apply -k observability/overlays/connected/   # optional"
