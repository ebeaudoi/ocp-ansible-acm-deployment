# Red Hat Advanced Cluster Management (RHACM)

Kustomize manifests for the ACM operator, MultiClusterHub, and observability.

## Purpose

Install RHACM on a hub cluster: operator → MultiClusterHub → optional observability
(object storage + MultiClusterObservability).

## From repo root

| File | Role |
|------|------|
| [`../update-values.sh`](../update-values.sh) | Patch RHACM channel / catalog / ose-cli image (`UPDATE_*` flags) |
| [`../deploy.yaml`](../deploy.yaml) | Deploy RHACM (`-e deploy_rhacm`, `-e deploy_observability`, `-e rhacm_overlay`) |

```bash
cd ..   # repo root
vim update-values.sh && ./update-values.sh
ansible-playbook deploy.yaml --tags rhacm
# Hub only, no object storage:
ansible-playbook deploy.yaml --tags rhacm -e deploy_observability=false
```

## Overlays

| Overlay | Catalog | InstallPlan | Channel default (edit in update-values.sh) |
|---------|---------|-------------|--------------------------------------------|
| `*/overlays/connected` | `redhat-operators` | Automatic | `release-2.17` |
| `*/overlays/airgapped` | Mirrored catalog | Manual | `release-2.12` |

Connected vs airgapped channel skew is intentional env defaults — change to match your catalog/mirror.

## What each folder does

| Path | Role |
|------|------|
| `operator/` | ACM Subscription + OperatorGroup |
| `instance/` | MultiClusterHub + MCE subscription annotation |
| `observability/` | Object-storage ConfigMap, setup Job, MultiClusterObservability |
| `overlays/{connected,airgapped}/` | Umbrella (day-2 re-apply only; first install use `deploy.yaml`) |

### Observability object storage

| File | Notes |
|------|--------|
| `observability/overlays/*/kustomization.yaml` | Patches for `OBJSTORE_*` + credentials RBAC (set via `update-values.sh`) |
| `observability/base/01-object-storage-config.yaml` | Base defaults; overlays override |
| `observability/base/02-f-observability-setup.yaml` | Creates pull-secret + `thanos-object-storage` |

Skip entirely with `-e deploy_observability=false`.

MCO PVCs use the cluster default StorageClass; patch `storageClass` in an overlay if needed.

## Prerequisites

- OpenShift 4.x, cluster-admin, `oc`
- Infra nodes (`node-role.kubernetes.io/infra`) via Subscription / MCH / MCO fields
- Object storage **or** `deploy_observability=false`

## Manual apply (debug)

```bash
export OVERLAY=connected   # or airgapped
cd rhacm

oc apply -k operator/overlays/${OVERLAY}/
# wait for CSV Succeeded

oc apply -k instance/overlays/${OVERLAY}/
oc wait mch multiclusterhub -n open-cluster-management \
  --for=jsonpath='{.status.phase}'=Running --timeout=1200s

oc apply -k observability/overlays/${OVERLAY}/
oc wait job/observability-setup -n open-cluster-management-observability \
  --for=condition=complete --timeout=600s
```

Day-2 full stack (CRDs already present):

```bash
oc apply -k overlays/${OVERLAY}/
```

## Layout

```
rhacm/
├── overlays/{connected,airgapped}/     # umbrella (operator+instance+observability)
├── operator/
│   ├── base/
│   ├── components/manual-approval/     # airgapped only
│   └── overlays/{connected,airgapped}/
├── instance/
│   ├── base/
│   └── overlays/{connected,airgapped}/
└── observability/
    ├── base/
    └── overlays/{connected,airgapped}/
```

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Operator / CSV never Succeeded | Catalog, channel, InstallPlan approval (airgapped) |
| Observability Job failing | Credentials Secret; `OBJSTORE_*` ConfigMap; Job logs |
| PVC Pending | Default StorageClass; set MCO `storageClass` |
| Pods on workers | Infra `nodeSelector` / tolerations on Subscription, MCH, MCO, Job |
