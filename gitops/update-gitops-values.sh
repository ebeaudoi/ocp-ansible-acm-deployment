#!/bin/bash
####################################################
# GitOps Operator Update Script                   #
# Updates kustomization.yaml files with new values #
####################################################

################################
# IMPORTANT                    #
# Update the variables below   #
################################
GITOPS_SUBSCRIPTION_CHANNEL="latest"
GITOPS_CATALOG_SOURCE="ebdn-redhat-operators"
#GITOPS_GIT_USER="admin"  # Uncomment if needed

################################
# Backup the files             #
################################
BACKUP_SUFFIX=$(date +%Y%m%d-%HH%M)
cp operator/overlays/infra/kustomization.yaml{,.${BACKUP_SUFFIX}}
cp instance/overlays/infra/kustomization.yaml{,.${BACKUP_SUFFIX}}
cp example-instance/overlays/airgapped/kustomization.yaml{,.${BACKUP_SUFFIX}}

################################
# Display configuration         #
################################
echo "=========================================="
echo "GitOps Operator Configuration"
echo "=========================================="
echo "  Subscription Channel: ${GITOPS_SUBSCRIPTION_CHANNEL}"
echo "  Catalog Source:       ${GITOPS_CATALOG_SOURCE}"
#echo "  Git User:             ${GITOPS_GIT_USER}"
echo "=========================================="
echo ""

################################
# Update Operator Overlay       #
################################
echo "[GitOps Operator] Updating operator overlay..."
echo "  File: operator/overlays/infra/kustomization.yaml"

# Update subscription channel
sed -i "/path:\ \/spec\/channel/{ n; s/value: .*$/value: ${GITOPS_SUBSCRIPTION_CHANNEL}/g }" operator/overlays/infra/kustomization.yaml && \
    echo "    ✓ Updated subscription channel: ${GITOPS_SUBSCRIPTION_CHANNEL}" || \
    echo "    ✗ Failed to update subscription channel"

# Update subscription catalog source
sed -i "/path:\ \/spec\/source/{ n; s/value: .*$/value: ${GITOPS_CATALOG_SOURCE}/g }" operator/overlays/infra/kustomization.yaml && \
    echo "    ✓ Updated catalog source: ${GITOPS_CATALOG_SOURCE}" || \
    echo "    ✗ Failed to update catalog source"

echo ""

# Update GitOps instance (commented out - uncomment if needed)
#echo "[GitOps Instance] Updating instance overlay..."
#echo "  File: example-instance/overlays/airgapped/kustomization.yaml"
#sed -i "/path:\ \/users/{ n; s/value: .*$/value: ${GITOPS_GIT_USER}/g }" example-instance/overlays/airgapped/kustomization.yaml && \
#    echo "    ✓ Updated Git user: ${GITOPS_GIT_USER}" || \
#    echo "    ✗ Failed to update Git user"

echo "=========================================="
echo "GitOps Operator update completed successfully"
echo "=========================================="
