# OpenShift GitOps

Kustomize manifests for the OpenShift GitOps operator and Argo CD instance.

## Purpose

Install OpenShift GitOps: operator → Argo CD instance (with optional component patches).

## From repo root

| File | Role |
|------|------|
| [`../update-values.sh`](../update-values.sh) | Patch GitOps channel / catalog (`UPDATE_GITOPS`) |
| [`../deploy.yaml`](../deploy.yaml) | Deploy GitOps (`-e deploy_gitops`) |

```bash
cd ..   # repo root
vim update-values.sh && ./update-values.sh
ansible-playbook deploy.yaml --tags gitops
```

## Overlays

| Overlay | Path | Notes |
|---------|------|--------|
| Operator `connected` | `operator/overlays/connected/` | Catalog/channel (same naming as RHACM) |
| Instance `connected` | `instance/overlays/connected/` | Argo CD + active components |

## What each folder does

| Path | Role |
|------|------|
| `operator/` | GitOps Subscription in `openshift-gitops-operator` |
| `instance/` | Argo CD CR + component patches |
| `instance/components/` | Library of patches — only those listed in the overlay are active |
| `acm-clusterset/` | **Advanced / optional** ACM PolicyGenerator — **not** part of `deploy.yaml` |

### gitops-admins (important)

The `gitops-admins` Group starts with `users: []`. Deploy succeeds, but **no human** has Argo CD admin via that group until you add users in:

`instance/overlays/connected/gitops-admins-group.yaml`

## Prerequisites

- OpenShift 4.x, cluster-admin, `oc`
- Catalog (`redhat-operators` or a mirror)
- Infra nodes — Subscription sets `nodeSelector` / tolerations

## Manual apply (debug)

```bash
cd gitops
oc apply -k operator/overlays/connected/
# wait for CSV Succeeded in openshift-gitops-operator
oc apply -k instance/overlays/connected/
oc rollout status deployment/openshift-gitops-server -n openshift-gitops
```

## Layout

```
gitops/
├── operator/
│   ├── base/
│   ├── components/openshift-gitops-operator/
│   └── overlays/connected/
├── instance/
│   ├── base/
│   ├── components/          # optional library + overlay-selected set
│   └── overlays/connected/
└── acm-clusterset/          # advanced ACM policies (separate from deploy.yaml)
```

## Troubleshooting

| Symptom | Check |
|---------|--------|
| CSV never Succeeded | Catalog / channel |
| `openshift-gitops-server` missing | Wait for operator to create Deployments; `oc get deploy -n openshift-gitops` |
| No Argo CD admin for humans | Fill `gitops-admins-group.yaml` users |

## ACM clusterset (optional)

See [acm-clusterset/README.md](acm-clusterset/README.md). Not required for `deploy.yaml`.
