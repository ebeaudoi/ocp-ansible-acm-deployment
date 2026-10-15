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
- For RHACM observability: deploy **S4** first (Thanos uses the S4 S3 API)
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

## Suggested order

1. **S4** (required before full ACM deploy with observability)  
2. **RHACM** full stack via `rhacm/deploy-rhacm.yaml` (or umbrella `overlays/`)  
3. **GitOps** when wiring Argo CD / ACM clusterset policies — see [`gitops/`](gitops/)
