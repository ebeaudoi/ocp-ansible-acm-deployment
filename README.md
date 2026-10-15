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

### 1. Set environment values

Choose the script that matches your cluster:

```bash
cd rhacm

# Connected (redhat-operators, Automatic InstallPlan)
vim update-rhacm-values-connected.sh
./update-rhacm-values-connected.sh

# Air-gapped (mirrored catalog, Manual InstallPlan)
# vim update-rhacm-values.sh && ./update-rhacm-values.sh
```

```bash
export OVERLAY=connected   # or: airgapped
```

### 2. Operator

```bash
oc apply -k operator/overlays/${OVERLAY}/
```

**Air-gapped only** — InstallPlan approval is Manual. Approve when ready:

```bash
oc get installplan -n open-cluster-management
oc patch installplan <name> -n open-cluster-management \
  --type merge -p '{"spec":{"approved":true}}'
```

Wait for the CSV:

```bash
oc wait csv -n open-cluster-management \
  -l operators.coreos.com/advanced-cluster-management.open-cluster-management \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
```

### 3. MultiClusterHub

```bash
oc apply -k instance/overlays/${OVERLAY}/
oc wait mch multiclusterhub -n open-cluster-management \
  --for=jsonpath='{.status.phase}'=Running --timeout=1200s
```

### 4. Observability (optional)

Requires **S4** (see below). Apply only after MultiClusterHub is Running and S4
is healthy.

```bash
oc apply -k observability/overlays/${OVERLAY}/
oc wait job/observability-setup -n open-cluster-management-observability \
  --for=condition=complete --timeout=600s
```

### 5. Verify

```bash
oc get csv,mch -n open-cluster-management
oc get pods -n open-cluster-management
oc get mco observability   # if deployed
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

1. **RHACM** operator → MultiClusterHub  
2. **S4** (required before ACM observability; also useful for logging buckets)  
3. **RHACM observability** (optional; Thanos object store → S4 bucket `acm-observability`)  
4. **GitOps** when wiring Argo CD / ACM clusterset policies — see [`gitops/`](gitops/)

RHACM hub and S4 can be deployed independently; observability depends on S4.
