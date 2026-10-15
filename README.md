# ocp-ansible-acm-deployment

Kustomize and Ansible manifests to deploy **RHACM**, optional **S4**
S3-compatible storage, and **OpenShift GitOps** on OpenShift (lab or air-gapped).

## Contents

1. [Repository layout](#repository-layout)
2. [Prerequisites](#prerequisites)
3. [Suggested deploy order](#suggested-deploy-order)
4. [Deploy S4](#deploy-s4)
5. [Deploy RHACM](#deploy-rhacm)
6. [Using a different S3 store](#using-a-different-s3-store-for-acm-observability)
7. [Detailed docs](#detailed-docs)

---

## Repository layout

| Path | Purpose | Guide |
|------|---------|--------|
| [`rhacm/`](rhacm/) | ACM operator, MultiClusterHub, observability | [rhacm/README.md](rhacm/README.md) |
| [`s4/`](s4/) | In-cluster S3-compatible storage (UI + API) | [s4/README.md](s4/README.md) |
| [`gitops/`](gitops/) | OpenShift GitOps / Argo CD / ACM clusterset | [gitops/README.md](gitops/README.md) · [acm-clusterset](gitops/acm-clusterset/README.md) |

```
.
├── rhacm/     # ACM hub + observability
├── s4/        # S3-compatible storage app
└── gitops/    # GitOps operator / Argo CD
```

---

## Prerequisites

| Need | Notes |
|------|--------|
| OpenShift 4.x + cluster-admin | Hub cluster |
| `oc` | On your PATH |
| Ansible + `kubernetes.core` | For `deploy-s4.yaml` / `deploy-rhacm.yaml` |
| Kubeconfig | `$KUBECONFIG` or `~/ocpkubeconfig` |
| Catalog (RHACM) | `redhat-operators` (connected) or a mirrored catalog (air-gapped) |
| Object storage (observability) | Default: **S4**. Alternatives: [different S3 store](#using-a-different-s3-store-for-acm-observability) |
| Infra nodes | RHACM workloads use `node-role.kubernetes.io/infra` |

Create kubeconfig (example):

```bash
oc login --server=<api-url> --token=<token>
oc config view --raw > "$HOME/ocpkubeconfig"
```

---

## Suggested deploy order

1. **Object storage** — [Deploy S4](#deploy-s4) (default), or configure another S3 backend  
2. **RHACM** — [Deploy RHACM](#deploy-rhacm)  
3. **GitOps** (optional) — see [`gitops/`](gitops/)

---

## Deploy S4

Full detail: [s4/README.md](s4/README.md).

S4 provides an S3 API and web UI. ACM observability uses it by default for Thanos.

### Configure

```bash
cd s4
vim overlays/lab/s4-secret-patch.yaml      # UI + S3 keys (change defaults)
vim overlays/lab/s4-route-s3-patch.yaml    # S3 API hostname for your cluster
```

### Deploy (Ansible)

```bash
cd s4
ansible-playbook deploy-s4.yaml \
  -e s4_bucket_name=loggingstack \
  -e s4_namespace=s4
```

### Deploy (`oc` only)

```bash
cd s4
oc create namespace s4 --dry-run=client -o yaml | oc apply -f -
oc apply -k overlays/lab -n s4
oc rollout status deployment/s4 -n s4 --timeout=600s
```

### Verify

```bash
oc get pods,route,pvc -n s4
oc get route s4 -n s4 -o jsonpath='{.spec.host}{"\n"}'       # UI
oc get route s4-api -n s4 -o jsonpath='{.spec.host}{"\n"}'   # S3 API
```

---

## Deploy RHACM

Full detail: [rhacm/README.md](rhacm/README.md).

Default path expects **S4 already running** (namespace `s4`, secret `s4-credentials`).

### Full stack (recommended)

Umbrella overlays: `rhacm/overlays/{connected,airgapped}/`  
(operator + MultiClusterHub + observability).

First install must be **staged** (CRDs appear after the operator). Use Ansible:

```bash
cd rhacm
# optional: ./update-rhacm-values-connected.sh
ansible-playbook deploy-rhacm.yaml                         # connected
ansible-playbook deploy-rhacm.yaml -e rhacm_overlay=airgapped
```

Day-2 re-apply (CRDs already present):

```bash
cd rhacm
oc apply -k overlays/connected/
```

### Verify

```bash
oc get csv,mch -n open-cluster-management
oc get pods -n open-cluster-management
oc get mco observability
```

Manual stage-by-stage commands: [rhacm/README.md](rhacm/README.md).

---

## Using a different S3 store for ACM observability

Default: Thanos object storage is filled by the observability setup Job from **S4**.

Any S3-compatible backend works (AWS S3, MinIO, NooBaa, Ceph RGW, etc.) if Thanos
can reach the endpoint and you provide access keys.

### Files to update

| File | Change |
|------|--------|
| [`rhacm/observability/base/01-s4-thanos-config.yaml`](rhacm/observability/base/01-s4-thanos-config.yaml) | Endpoint, bucket, secret name/namespace, insecure flag |
| [`rhacm/observability/base/02-g-s4-credentials-role.yaml`](rhacm/observability/base/02-g-s4-credentials-role.yaml) | Namespace + Secret `resourceNames` |
| [`rhacm/observability/base/02-h-s4-credentials-rolebinding.yaml`](rhacm/observability/base/02-h-s4-credentials-rolebinding.yaml) | Same namespace |
| [`rhacm/observability/base/02-f-observability-setup.yaml`](rhacm/observability/base/02-f-observability-setup.yaml) | Skip S4 bucket-create API if not using S4 |
| [`rhacm/deploy-rhacm.yaml`](rhacm/deploy-rhacm.yaml) | Soften/remove S4 preflight if S4 is not deployed |
| *(new)* credentials Secret | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` |

### How it works today (S4)

| Resource | Role |
|----------|------|
| ConfigMap `s4-thanos-config` | Endpoint / bucket / where to read credentials |
| Secret `s4/s4-credentials` | Access keys (+ UI keys for S4 bucket API) |
| Job `observability-setup` | Writes Secret `thanos-object-storage` |
| MultiClusterObservability | Reads `thanos-object-storage` → `thanos.yaml` |

### Option A — Retarget the setup Job

1. Create a credentials Secret (any namespace):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-s3-credentials
  namespace: my-s3-ns
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: <access-key>
  AWS_SECRET_ACCESS_KEY: <secret-key>
```

2. Set ConfigMap keys:

| Key | S4 default | Your value |
|-----|------------|------------|
| `S4_NAMESPACE` | `s4` | Credentials Secret namespace |
| `S4_SECRET_NAME` | `s4-credentials` | Credentials Secret name |
| `S4_ENDPOINT` | `s4.s4.svc:7480` | S3 host:port (**no** `https://`) |
| `S4_BUCKET` | `acm-observability` | Bucket name (create it first) |
| `S4_INSECURE` | `true` | `false` if TLS is valid |
| `S4_API_URL` | S4 management API | Unused unless Job still creates buckets via S4 |

3. Point RBAC (`02-g` / `02-h`) at that Secret.  
4. Pre-create the bucket (or keep S4-only bucket-create logic).  
5. Skip S4 deploy; adjust `deploy-rhacm.yaml` preflight if needed.

Example (AWS S3, bucket already exists):

```yaml
data:
  S4_NAMESPACE: my-s3-ns
  S4_SECRET_NAME: my-s3-credentials
  S4_ENDPOINT: s3.us-east-1.amazonaws.com
  S4_BUCKET: acm-observability
  S4_INSECURE: "false"
  S4_API_URL: ""
```

### Option B — Provide `thanos-object-storage` yourself

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: thanos-object-storage
  namespace: open-cluster-management-observability
type: Opaque
stringData:
  thanos.yaml: |
    type: s3
    config:
      bucket: acm-observability
      endpoint: s3.us-east-1.amazonaws.com
      insecure: false
      access_key: <access-key>
      secret_key: <secret-key>
```

Then skip/disable the Job’s object-store creation (keep pull-secret logic if needed).
MCO already references this Secret name/key.

### Notes

- Prefer in-cluster DNS for on-cluster stores; use a cloud hostname for AWS/MinIO external.
- `insecure: false` needs a trusted CA (cluster proxy/CA may be required).
- MCO **PVC** StorageClass is separate from object storage—patch if the cluster default is wrong.

---

## Detailed docs

| Topic | Doc |
|-------|-----|
| RHACM overlays, update scripts, troubleshooting | [rhacm/README.md](rhacm/README.md) |
| S4 architecture and options | [s4/README.md](s4/README.md) |
| GitOps / ACM clusterset | [gitops/README.md](gitops/README.md) |
