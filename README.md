# ocp-ansible-acm-deployment

Deploy **RHACM** and **OpenShift GitOps** on OpenShift with Kustomize + Ansible.
Optional **S4** (or any other S3) for ACM observability object storage.

## Contents

1. [Architecture](#architecture)
2. [Two files you need](#two-files-you-need)
3. [Pre-flight checklist](#pre-flight-checklist)
4. [Quick start](#quick-start)
5. [Toggles: UPDATE_* vs deploy_*](#toggles-update_-vs-deploy_)
6. [Verify success](#verify-success)
7. [Repository layout](#repository-layout)
8. [Object storage for observability](#object-storage-for-observability)
9. [Troubleshooting](#troubleshooting)
10. [Detailed docs](#detailed-docs)

---

## Architecture

```
update-values.sh  →  patches overlays only
object storage    →  ready (or deploy_observability=false)
deploy.yaml       →  RHACM operator → MultiClusterHub → Observability Job + MCO
                  →  GitOps operator → Argo CD instance
```

| Stage | What gets installed |
|-------|---------------------|
| RHACM operator | Subscription / CSV in `open-cluster-management` |
| MultiClusterHub | Hub instance (`mch multiclusterhub`) |
| Observability | Setup Job + `MultiClusterObservability` (optional) |
| GitOps operator | Subscription / CSV in `openshift-gitops-operator` |
| Argo CD | Instance in `openshift-gitops` |

---

## Two files you need

| File | Purpose |
|------|---------|
| [`update-values.sh`](update-values.sh) | **Only** place to edit channels, catalogs, images (does **not** deploy) |
| [`deploy.yaml`](deploy.yaml) | **Only** playbook to deploy RHACM and/or GitOps |

```bash
vim update-values.sh
./update-values.sh
ansible-playbook deploy.yaml
```

---

## Pre-flight checklist

| Check | Notes |
|-------|--------|
| OpenShift 4.x + cluster-admin | Hub cluster |
| `oc` + Ansible + `kubernetes.core` | Workstation |
| Kubeconfig | `$KUBECONFIG` or `~/ocpkubeconfig`; `oc whoami` works |
| Catalog | `redhat-operators` (connected) or mirrored catalog (airgapped) |
| Infra nodes | `node-role.kubernetes.io/infra` (NoSchedule is enough) |
| Object storage **or** skip | S4 / AWS / MinIO configured under `rhacm/observability/`, **or** `-e deploy_observability=false` |
| Edit `update-values.sh` | Channels / catalogs / images match your environment |
| GitOps admins | Fill `gitops/instance/overlays/connected/gitops-admins-group.yaml` if humans need Argo CD admin |

```bash
oc login --server=<api-url> --token=<token>
oc config view --raw > "$HOME/ocpkubeconfig"
```

---

## Quick start

### Configure

1. **TOGGLE** in [`update-values.sh`](update-values.sh) — `UPDATE_RHACM_CONNECTED`, `UPDATE_RHACM_AIRGAPPED`, `UPDATE_GITOPS`
2. **RHACM / GITOPS** values — channel, catalog, ose-cli image
3. Run `./update-values.sh`

### Deploy

```bash
ansible-playbook deploy.yaml
```

```bash
ansible-playbook deploy.yaml -e rhacm_overlay=airgapped
ansible-playbook deploy.yaml -e deploy_observability=false   # ACM hub without object storage
ansible-playbook deploy.yaml -e deploy_gitops=false
ansible-playbook deploy.yaml -e deploy_rhacm=false
ansible-playbook deploy.yaml --tags rhacm
ansible-playbook deploy.yaml --tags gitops
```

The playbook does **not** validate S4/S3. That is your responsibility.

### Optional: deploy S4 first

```bash
cd s4
vim overlays/lab/s4-secret-patch.yaml
vim overlays/lab/s4-route-s3-patch.yaml
ansible-playbook deploy-s4.yaml
cd ..
```

---

## Toggles: UPDATE_* vs deploy_*

| Flag | Where | Effect |
|------|--------|--------|
| `UPDATE_RHACM_CONNECTED` / `UPDATE_RHACM_AIRGAPPED` / `UPDATE_GITOPS` | `update-values.sh` | Which overlays get **patched** |
| `-e deploy_rhacm=` | `deploy.yaml` | Whether RHACM is **installed** |
| `-e deploy_observability=` | `deploy.yaml` | Whether observability Job + MCO are applied (default `true`) |
| `-e deploy_gitops=` | `deploy.yaml` | Whether GitOps is **installed** |
| `-e rhacm_overlay=` | `deploy.yaml` | `connected` (default) or `airgapped` |

---

## Verify success

```bash
# RHACM
oc get csv,mch -n open-cluster-management
oc get mco observability   # if observability was deployed

# GitOps
oc get csv -n openshift-gitops-operator
oc get argocd,route -n openshift-gitops
oc get group gitops-admins -o yaml   # users should not be empty for human admins
```

---

## Repository layout

```
.
├── update-values.sh     # edit all project parameters here
├── deploy.yaml          # deploy RHACM + GitOps
├── rhacm/               # ACM kustomize (operator / instance / observability)
├── gitops/              # GitOps kustomize (operator / instance)
└── s4/                  # optional in-cluster S3 app
```

| Path | Guide |
|------|--------|
| [`rhacm/`](rhacm/) | [rhacm/README.md](rhacm/README.md) |
| [`gitops/`](gitops/) | [gitops/README.md](gitops/README.md) |
| [`s4/`](s4/) | [s4/README.md](s4/README.md) |

---

## Object storage for observability

Defaults target **S4**. For AWS S3 / MinIO / other S3:

| File | What |
|------|------|
| [`rhacm/observability/base/01-object-storage-config.yaml`](rhacm/observability/base/01-object-storage-config.yaml) | `OBJSTORE_*` endpoint, bucket, secret location; leave `OBJSTORE_API_URL` empty if no management API |
| [`rhacm/observability/base/02-g-object-storage-credentials-role.yaml`](rhacm/observability/base/02-g-object-storage-credentials-role.yaml) | RBAC namespace/secret must match ConfigMap — **that namespace must already exist** before apply (default `s4`) |
| [`rhacm/observability/base/02-h-object-storage-credentials-rolebinding.yaml`](rhacm/observability/base/02-h-object-storage-credentials-rolebinding.yaml) | Same |
| [`rhacm/observability/base/02-f-observability-setup.yaml`](rhacm/observability/base/02-f-observability-setup.yaml) | Creates `thanos-object-storage` Secret |

Or create Secret `thanos-object-storage` yourself in `open-cluster-management-observability`.

MCO PVCs use the **cluster default StorageClass**. Set `spec.storageConfig.storageClass` in an overlay if the default is unsuitable.

---

## Troubleshooting

| Symptom | Likely cause | What to check |
|---------|--------------|---------------|
| Preflight fails | Missing kubeconfig / `oc` | Path, `oc whoami` |
| CSV never resolves | Catalog / channel / InstallPlan | `oc get sub,ip,csv -n open-cluster-management`; airgapped needs approval |
| Observability Job timeout | Missing credentials / wrong endpoint | `oc logs -n open-cluster-management-observability job/observability-setup`; ConfigMap `observability-object-storage` |
| GitOps server Deployment missing | Operator not ready yet | Playbook waits for Deployment existence; `oc get deploy -n openshift-gitops` |
| PVC Pending | No/wrong default StorageClass | Patch MCO `storageClass` |
| Argo CD works but no human admin | Empty `gitops-admins` users | Edit overlay Group and re-apply |

---

## Detailed docs

| Topic | Doc |
|-------|-----|
| RHACM overlays | [rhacm/README.md](rhacm/README.md) |
| GitOps | [gitops/README.md](gitops/README.md) |
| S4 | [s4/README.md](s4/README.md) |
| ACM GitOps policies (optional) | [gitops/acm-clusterset/README.md](gitops/acm-clusterset/README.md) |
