#!/bin/bash
####################################################
# RHACM Operator Update Script                     #
# Updates overlay kustomization.yaml values        #
####################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

################################
# IMPORTANT                    #
# Update the variables below   #
################################
RHACM_SUBSCRIPTION_CHANNEL="release-2.12"
RHACM_CATALOG_SOURCE="ebdn-redhat-operators"
# Prefer an internal registry mirror @sha256 for air-gapped clusters
RHACM_OSE_CLI_IMAGE="registry.redhat.io/openshift4/ose-cli@sha256:3b288bdf503733042786c07ab23ba344c8ad98a38717c192584d0e1926ae9758"

OPERATOR_OVERLAY="operator/overlays/airgapped/kustomization.yaml"
INSTANCE_OVERLAY="instance/overlays/airgapped/kustomization.yaml"
OBSERVABILITY_OVERLAY="observability/overlays/airgapped/kustomization.yaml"

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
echo "RHACM Operator Configuration"
echo "=========================================="
echo "  Subscription Channel: ${RHACM_SUBSCRIPTION_CHANNEL}"
echo "  Catalog Source:       ${RHACM_CATALOG_SOURCE}"
echo "  OSE CLI Image:        ${RHACM_OSE_CLI_IMAGE}"
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
echo "[RHACM Operator] Updating operator overlay..."
echo "  File: ${OPERATOR_OVERLAY}"
replace_json6902_value "${OPERATOR_OVERLAY}" "/spec/channel" "${RHACM_SUBSCRIPTION_CHANNEL}"
echo "    Updated subscription channel: ${RHACM_SUBSCRIPTION_CHANNEL}"
replace_json6902_value "${OPERATOR_OVERLAY}" "/spec/source" "${RHACM_CATALOG_SOURCE}"
echo "    Updated catalog source: ${RHACM_CATALOG_SOURCE}"
echo ""

################################
# Update Observability Overlay  #
################################
echo "[RHACM Observability] Updating observability overlay..."
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
echo "[RHACM Instance] Updating MultiClusterHub instance overlay..."
echo "  File: ${INSTANCE_OVERLAY}"
MCE_VALUE="{\"source\": \"${RHACM_CATALOG_SOURCE}\"}"
# Keep single-quoted YAML scalar so JSON braces are preserved
replace_json6902_value \
  "${INSTANCE_OVERLAY}" \
  "/metadata/annotations/installer.open-cluster-management.io~1mce-subscription-spec" \
  "'${MCE_VALUE}'"
echo "    Updated MCE subscription spec with catalog: ${RHACM_CATALOG_SOURCE}"
echo ""

echo "=========================================="
echo "RHACM Operator update completed successfully"
echo "=========================================="
echo "Backups written with suffix: .${BACKUP_SUFFIX}"
echo "(Ignored by rhacm/.gitignore)"
