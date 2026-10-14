# S4 — S3-compatible object storage on OpenShift

S4 deploys a lightweight S3-compatible storage stack (RGW-backed UI + S3 API) into
an OpenShift cluster using Kustomize, with an optional Ansible playbook that
applies the manifests and creates an initial bucket.

Image: `quay.io/rh-aiservices-bu/s4:latest`

## Architecture

```
                    ┌─────────────────────────────┐
   Browser / API    │  Route s4 (UI :5000, TLS)   │
                    │  Route s4-api (S3 :7480)    │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────▼───────────────┐
                    │  Service s4 (ClusterIP)     │
                    │  (+ optional NodePort)      │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────▼───────────────┐
                    │  Deployment s4 (1 replica)  │
                    │  ConfigMap + Secret env     │
                    │  PVC s4-data → /var/lib/... │
                    └─────────────────────────────┘
```

| Resource | Purpose |
|----------|---------|
| `s4-config` ConfigMap | Non-secret settings (region, port, transfer limits) |
| `s4-credentials` Secret | S3 keys + UI username/password |
| `s4-data` PVC | Persistent RGW data (default 10Gi, RWO) |
| Deployment `s4` | Single replica, Recreate strategy (RWO-safe) |
| Service `s4` | ClusterIP for UI (5000) and S3 API (7480) |
| Route `s4` | Edge-terminated UI route |
| Route `s4-api` | Edge-terminated external S3 API route |

## Directory layout

```
s4/
├── deploy-s4.yaml          # Ansible: apply overlay + create bucket
├── base/                   # Shared manifests
│   ├── kustomization.yaml
│   ├── s4-configmap.yaml
│   ├── s4-secret.yaml      # Placeholder credentials (override in overlay)
│   ├── s4-pvc.yaml
│   ├── s4-deployment.yaml
│   ├── s4-service.yaml
│   ├── s4-route.yaml       # UI
│   └── s4-route-s3.yaml    # S3 API
└── overlays/
    └── lab/                # Lab environment patches
        ├── kustomization.yaml
        ├── s4-secret-patch.yaml
        └── s4-route-s3-patch.yaml
```

Optional / unused in the current build (not listed in `base/kustomization.yaml`):

- `base/s4-ingress-s3.yaml` — Kubernetes Ingress alternative to the OpenShift Route
- `base/ca.crt`, `s4-api.crt`, `service-ca.crt` — leftover cert files; not mounted by the Deployment

## Prerequisites

- OpenShift cluster with a default StorageClass (or edit the PVC)
- `oc` logged in (or a kubeconfig file)
- For Ansible deploy:
  - Ansible with `kubernetes.core` collection
  - `oc` on `PATH`
  - Kubeconfig at `$KUBECONFIG`, or `~/ocpkubeconfig` if unset

## Configure before deploy

### 1. Credentials (required)

Edit the lab overlay secret patch (do **not** leave `changeme` in shared/lab clusters):

```bash
vim overlays/lab/s4-secret-patch.yaml
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: s4-credentials
stringData:
  AWS_ACCESS_KEY_ID: <s3-access-key>
  AWS_SECRET_ACCESS_KEY: <s3-secret-key>
  UI_USERNAME: <ui-user>
  UI_PASSWORD: <strong-password>
```

### 2. S3 API Route host

Lab overlay pins the external S3 hostname:

```bash
vim overlays/lab/s4-route-s3-patch.yaml
```

Set `spec.host` to a valid hostname on your cluster’s apps domain, for example:

`s3.s4.apps.<cluster-domain>`

The UI Route (`s4`) uses the default OpenShift-generated host unless you set one
in `base/s4-route.yaml`.

### 3. New environments

Copy the lab overlay:

```bash
cp -a overlays/lab overlays/prod
# edit secret + route host
```

Then deploy with `S4_OVERLAY=prod` or `-e s4_overlay=prod`.

## Deploy with Ansible (recommended)

From this directory (`rhacm/s4`):

```bash
cd rhacm/s4

# Optional overrides
export KUBECONFIG=~/ocpkubeconfig
export S4_OVERLAY=lab

ansible-playbook deploy-s4.yaml \
  -e s4_bucket_name=loggingstack \
  -e s4_namespace=s4
```

The playbook will:

1. Ensure namespace `s4` exists
2. `oc kustomize overlays/<overlay>` and apply the manifests
3. Roll out restart Deployment `s4` and wait for readiness
4. Wait for the UI Route and `/api/auth/info`
5. Log in (if auth is required) and create bucket `loggingstack` (idempotent; 409 = already exists)

## Deploy with oc only

```bash
cd rhacm/s4
oc create namespace s4 --dry-run=client -o yaml | oc apply -f -
oc apply -k overlays/lab -n s4
oc rollout status deployment/s4 -n s4 --timeout=600s
```

Create a bucket via the UI:

```bash
oc get route s4 -n s4
# Open https://<host>/ and sign in with UI_USERNAME / UI_PASSWORD
```

Or call the S3/API endpoints using the access keys from `s4-credentials`.

## Verify

```bash
oc get pods,svc,route,pvc -n s4
oc get secret s4-credentials -n s4
oc logs -n s4 deploy/s4 --tail=50

# UI
oc get route s4 -n s4 -o jsonpath='{.spec.host}{"\n"}'

# External S3 API
oc get route s4-api -n s4 -o jsonpath='{.spec.host}{"\n"}'
```

Example S3 client pointing at the API route (access key / secret from the Secret):

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
aws --endpoint-url https://$(oc get route s4-api -n s4 -o jsonpath='{.spec.host}') \
  s3 ls
```

(Disable TLS verify only in lab if using a non-public CA.)

## Design assessment

### What works well

- Clear **base + overlay** split (lab patches credentials and S3 route host)
- Secret vs ConfigMap separation for credentials
- Restricted container security context (`runAsNonRoot`, drop ALL caps, RuntimeDefault seccomp)
- Resource requests/limits and HTTP readiness/liveness on the UI port
- Recreate deployment strategy fits RWO PVC
- Ansible flow covers apply, wait, and idempotent bucket creation
- Labels follow `app.kubernetes.io/*` conventions

### Gaps / recommendations

| Item | Severity | Note |
|------|----------|------|
| Default UI password `changeme` in base + lab | High | Change before any shared cluster deploy |
| Image tag `:latest` + `imagePullPolicy: Always` | Medium | Pin digest for air-gapped / reproducible deploys |
| NodePort Service always applied | Low | Prefer ClusterIP + Routes only unless NodePort is required |
| Unused cert files and Ingress in `base/` | Low | Remove or document; they are not applied today |
| No `storageClassName` on PVC | Low | Relies on cluster default StorageClass |
| Playbook always `rollout restart` | Low | Forces bounce even when manifests unchanged |
| Single replica only | Info | Expected with RWO; HA would need RWX + app support |

The Ansible playbook path was corrected to render `overlays/<name>` relative to
this folder (`playbook_dir`), and kubeconfig resolution prefers `$KUBECONFIG`.

## Troubleshooting

- **PVC Pending**: Check default StorageClass / capacity; edit `base/s4-pvc.yaml`
- **ImagePullBackOff**: Ensure the cluster can pull `quay.io/rh-aiservices-bu/s4` (or mirror it)
- **Route host rejected**: Align `s4-route-s3-patch.yaml` with the cluster apps domain
- **Ansible cannot find kubeconfig**: Set `KUBECONFIG` or place a kubeconfig at `~/ocpkubeconfig`
- **Bucket create 401**: Confirm `UI_USERNAME` / `UI_PASSWORD` in the overlay secret match what the pod loaded (restart if you changed the Secret)
