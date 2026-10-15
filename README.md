# ocp-ansible-acm-deployment

Kustomize (and Ansible) manifests to deploy **Red Hat Advanced Cluster Management
(RHACM)**, optional **S4** S3-compatible storage, and related **OpenShift GitOps**
assets on OpenShift—typically in air-gapped or lab environments.

## Index

| Path | Description | Docs |
|------|-------------|------|
| [`rhacm/`](rhacm/) | RHACM operator, MultiClusterHub instance, and observability | [rhacm/README.md](rhacm/README.md) |
| [`s4/`](s4/) | S3-compatible object storage (UI + S3 API) on OpenShift | [s4/README.md](s4/README.md) |
| [`gitops/`](gitops/) | OpenShift GitOps operator, example instance, ACM clusterset | [gitops/README.md](gitops/README.md), [gitops/acm-clusterset/README.md](gitops/acm-clusterset/README.md) |

```
.
├── rhacm/          # ACM hub + observability
├── s4/             # S3-compatible storage app
└── gitops/         # GitOps operator / Argo CD / ACM integration
```

## Prerequisites (shared)

- OpenShift 4.x cluster and cluster-admin access
- `oc` CLI
- For RHACM air-gapped: mirrored Red Hat catalog
- For RHACM observability (default path): deploy **S4** first (Thanos uses S4’s
  S3 API). To use another S3 backend instead, see
  [Using a different S3 store for ACM observability](#using-a-different-s3-store-for-acm-observability)
- For S4 Ansible deploy: Ansible with `kubernetes.core`, plus `oc` on `PATH`

---

## Deploy RHACM

Full detail: [rhacm/README.md](rhacm/README.md).

Workloads are pinned to **infra nodes** via Subscription / MultiClusterHub / MCO
fields (not namespace scheduler annotations).

**Prerequisite:** S4 must already be deployed (`s4/deploy-s4.yaml`).

### Full stack (recommended)

Umbrella kustomizations live at `rhacm/overlays/{connected,airgapped}/` (operator
+ instance + observability). First install must be staged because CRDs appear
asynchronously — use the deploy script:

```bash
cd rhacm
# optional: ./update-rhacm-values-connected.sh
ansible-playbook deploy-rhacm.yaml                         # connected (default)
ansible-playbook deploy-rhacm.yaml -e rhacm_overlay=airgapped
```

Day-2 re-apply (CRDs already present):

```bash
oc apply -k overlays/connected/
```

### Manual staged steps

See [rhacm/README.md](rhacm/README.md) for operator → instance → observability
commands if you need to debug a single stage.

### Verify

```bash
oc get csv,mch -n open-cluster-management
oc get pods -n open-cluster-management
oc get mco observability
```

---

## Deploy S4

Full detail: [s4/README.md](s4/README.md).

S4 provides an S3-compatible API and web UI. Configure credentials and the S3
route host in the lab overlay before applying.

### 1. Configure overlay

```bash
cd s4
vim overlays/lab/s4-secret-patch.yaml      # UI + S3 keys (change defaults)
vim overlays/lab/s4-route-s3-patch.yaml    # S3 API hostname for your cluster
```

### 2. Deploy with Ansible (recommended)

```bash
export KUBECONFIG=~/ocpkubeconfig   # or your kubeconfig
export S4_OVERLAY=lab

ansible-playbook deploy-s4.yaml \
  -e s4_bucket_name=loggingstack \
  -e s4_namespace=s4
```

The playbook applies the overlay, waits for the Deployment, and creates the
bucket (idempotent).

### 3. Or deploy with oc only

```bash
cd s4
oc create namespace s4 --dry-run=client -o yaml | oc apply -f -
oc apply -k overlays/lab -n s4
oc rollout status deployment/s4 -n s4 --timeout=600s
```

### 4. Verify

```bash
oc get pods,route,pvc -n s4
oc get route s4 -n s4 -o jsonpath='{.spec.host}{"\n"}'       # UI
oc get route s4-api -n s4 -o jsonpath='{.spec.host}{"\n"}'   # S3 API
```

---

## Using a different S3 store for ACM observability

By default, ACM observability expects **S4** and builds the Thanos object-store
Secret from:

| Resource | Role |
|----------|------|
| [`rhacm/observability/base/01-s4-thanos-config.yaml`](rhacm/observability/base/01-s4-thanos-config.yaml) | Endpoint, bucket, secret location |
| Secret `s4/s4-credentials` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (and UI keys for bucket create) |
| Job `observability-setup` | Creates `thanos-object-storage` consumed by MultiClusterObservability |

Any **S3-compatible** store works (AWS S3, MinIO, NooBaa, Ceph RGW, cloud object
storage) if Thanos can reach it and you supply access keys.

### Option A — Point the existing setup Job at another S3 (minimal change)

1. Create a Secret in some namespace with at least:

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
     # Optional: only needed if the Job should create the bucket via S4-style API
     # UI_USERNAME: ...
     # UI_PASSWORD: ...
   ```

2. Patch ConfigMap values (overlay patch or edit the base ConfigMap):

   | Key | Default (S4) | Change to |
   |-----|----------------|-----------|
   | `S4_NAMESPACE` | `s4` | Namespace of your credentials Secret |
   | `S4_SECRET_NAME` | `s4-credentials` | Your Secret name |
   | `S4_ENDPOINT` | `s4.s4.svc:7480` | S3 API host:port (no `https://`) |
   | `S4_BUCKET` | `acm-observability` | Existing bucket name |
   | `S4_INSECURE` | `true` | `false` if TLS is valid; `true` for HTTP/lab |
   | `S4_API_URL` | `http://s4.s4.svc:5000/api` | Only used to **create** the bucket via S4’s management API |

3. Update RBAC so the setup Job can read that Secret (today:
   [`02-g-s4-credentials-role.yaml`](rhacm/observability/base/02-g-s4-credentials-role.yaml) /
   [`02-h-s4-credentials-rolebinding.yaml`](rhacm/observability/base/02-h-s4-credentials-rolebinding.yaml)
   target namespace `s4` and secret `s4-credentials`). Point those at your
   namespace / secret name, or add equivalent Role + RoleBinding.

4. **Bucket creation:** create the bucket ahead of time in your S3 console/CLI.
   If you are not using S4’s UI API, either pre-create the bucket or adjust the
   Job so it skips the `S4_API_URL` bucket-create step (otherwise that curl will
   fail against a non-S4 endpoint).

5. Skip deploying S4 and run ACM as usual. Soften S4 checks in
   `rhacm/deploy-rhacm.yaml` (or apply operator/instance/observability overlays
   manually) if you no longer use S4.

Example ConfigMap for AWS S3 (bucket already exists):

```yaml
data:
  S4_NAMESPACE: my-s3-ns
  S4_SECRET_NAME: my-s3-credentials
  S4_ENDPOINT: s3.us-east-1.amazonaws.com
  S4_BUCKET: acm-observability
  S4_INSECURE: "false"
  # Leave S4_API_URL unused only if Job bucket-create is removed/skipped
  S4_API_URL: ""
```

### Option B — Provide `thanos-object-storage` yourself (bypass S4 Job logic)

Create the Secret MultiClusterObservability already references:

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

Then either:

- Remove or disable the bucket/credential portion of `observability-setup` (keep
  pull-secret creation if you still need it), or  
- Apply operator + instance + MCO without relying on the Job for object storage.

`MultiClusterObservability` continues to use:

```yaml
spec:
  storageConfig:
    metricObjectStorage:
      name: thanos-object-storage
      key: thanos.yaml
```

### Notes

- **In-cluster vs external:** prefer an in-cluster Service DNS name when the
  store runs on the hub; use a public/private endpoint hostname for cloud S3.
- **TLS:** set `insecure: false` and ensure Thanos trusts the CA (cluster
  proxy/CA config may be required for private endpoints).
- **PVC StorageClass** for Alertmanager/compact/receive/store is separate from
  object storage; patch MCO if your cluster default StorageClass is wrong.
- Default path (S4) remains documented under [Deploy S4](#deploy-s4).

---

## Suggested order

1. **Object storage for observability** — default **S4**, or another S3 backend
   (see above)  
2. **RHACM** full stack via `rhacm/deploy-rhacm.yaml` (or umbrella `overlays/`)  
3. **GitOps** when wiring Argo CD / ACM clusterset policies — see [`gitops/`](gitops/)
