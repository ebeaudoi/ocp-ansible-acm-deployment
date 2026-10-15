# Red Hat Advanced Cluster Management (RHACM)

Deploy RHACM operator, MultiClusterHub, and optional observability using
Kustomize. Overlays support **air-gapped** and **connected** clusters.

| Overlay | Catalog | InstallPlan | OSE CLI image | Update script |
|---------|---------|-------------|---------------|---------------|
| `*/overlays/airgapped` | Mirrored catalog | Manual | Internal registry `@sha256` | `update-rhacm-values.sh` |
| `*/overlays/connected` | `redhat-operators` | Automatic | `registry.redhat.io/...` | `update-rhacm-values-connected.sh` |

## Prerequisites

- **OpenShift CLI (`oc`)**: Version 4.x or later
- **Cluster Access**: Admin access to the OpenShift cluster
- **Catalog Source**: `redhat-operators` (connected) or a mirrored catalog (air-gapped)
- **Infrastructure Nodes**: Workloads target `node-role.kubernetes.io/infra`
  via explicit `nodeSelector`/`tolerations` on Subscription, MultiClusterHub
  (including MCE `mce-subscription-spec` config), MultiClusterObservability, and
  the observability setup Job. Namespaces do **not** use
  `openshift.io/node-selector` or `scheduler.alpha.kubernetes.io/defaultTolerations`.
- **S4 (required before ACM with observability)**: Deploy [`s4/`](../s4/) first
  (`deploy-s4.yaml`). Observability stores Thanos metrics in an S4 S3 bucket
  (`acm-observability` by default) via the in-cluster Service `s4.s4.svc:7480`

## Full-stack deploy (recommended)

One umbrella kustomization composes operator + instance + observability:

| Overlay | Path |
|---------|------|
| Connected | [`overlays/connected/`](overlays/connected/) |
| Air-gapped | [`overlays/airgapped/`](overlays/airgapped/) |

A single `oc apply -k overlays/<env>/` declares the full desired state, but
**first-time install must be staged**: `MultiClusterHub` and
`MultiClusterObservability` CRDs only exist after the operator/MCH are ready.
Use the Ansible playbook (checks S4, applies in order, waits):

```bash
cd rhacm
# Optional: export KUBECONFIG or use ~/ocpkubeconfig (same as s4)
ansible-playbook deploy-rhacm.yaml                         # connected (default)
ansible-playbook deploy-rhacm.yaml -e rhacm_overlay=airgapped
# or: RHACM_OVERLAY=airgapped ansible-playbook deploy-rhacm.yaml
```

After CRDs exist (day-2 / re-apply):

```bash
oc apply -k overlays/connected/
```

## Update Scripts

Timestamped backups of overlay files are written beside each overlay and ignored
via `.gitignore`.

### Connected clusters

```bash
cd rhacm
vim update-rhacm-values-connected.sh
```

```bash
RHACM_SUBSCRIPTION_CHANNEL="release-2.12"
RHACM_CATALOG_SOURCE="redhat-operators"
RHACM_OSE_CLI_IMAGE="registry.redhat.io/openshift4/ose-cli:latest"
```

```bash
./update-rhacm-values-connected.sh
```

### Air-gapped clusters

```bash
cd rhacm
vim update-rhacm-values.sh
```

```bash
RHACM_SUBSCRIPTION_CHANNEL="release-2.12"
RHACM_CATALOG_SOURCE="your-redhat-catalog"
RHACM_OSE_CLI_IMAGE="registry.example.com/openshift4/ose-cli@sha256:..."
```

```bash
./update-rhacm-values.sh
```

## Deployment Steps (manual / staged)

Prefer [`deploy-rhacm.yaml`](deploy-rhacm.yaml) for a full install. The steps below
are the same flow broken out for debugging.

Set `OVERLAY` to `connected` or `airgapped`:

```bash
export OVERLAY=connected   # or: airgapped
cd rhacm
```

### 1. Deploy RHACM Operator

```bash
oc apply -k operator/overlays/${OVERLAY}/
```

**Air-gapped only:** InstallPlan approval is Manual. Approve when ready:

```bash
oc get installplan -n open-cluster-management
oc patch installplan <name> -n open-cluster-management \
  --type merge -p '{"spec":{"approved":true}}'
```

**Connected:** InstallPlan approval is Automatic; no patch is required.

### 2. Wait for the operator CSV

```bash
oc wait csv -n open-cluster-management \
  -l operators.coreos.com/advanced-cluster-management.open-cluster-management \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
```

### 3. Deploy MultiClusterHub

```bash
oc apply -k instance/overlays/${OVERLAY}/
oc wait mch multiclusterhub -n open-cluster-management \
  --for=jsonpath='{.status.phase}'=Running --timeout=1200s
```

For multi-replica hub components, add the HA component to the instance overlay:

```yaml
components:
  - ../../components/ha-availability
```

### 4. Deploy Observability (Optional)

Requires **S4** running in namespace `s4` (see [s4/README.md](../s4/README.md)).
Apply only after MultiClusterHub is Running.

```bash
# From repo root, if not already deployed:
# cd s4 && ansible-playbook deploy-s4.yaml && cd ../rhacm

oc apply -k observability/overlays/${OVERLAY}/
oc wait job/observability-setup -n open-cluster-management-observability \
  --for=condition=complete --timeout=600s
oc get mco observability
```

The setup Job reads `s4/s4-credentials`, ensures bucket `acm-observability`
exists on S4, and writes the `thanos-object-storage` Secret. Endpoint and bucket
are set in `observability/base/01-s4-thanos-config.yaml`.

To override PVC sizes, enable `observability/components/odf-storage-sizes` in the
overlay and edit the values there.

### 5. Verify

```bash
oc get csv -n open-cluster-management
oc get multiclusterhub -n open-cluster-management
oc get pods -n open-cluster-management
oc get pods -n open-cluster-management-observability   # if deployed
```

## Directory Structure

```
rhacm/
├── overlays/                    # Full stack (operator + instance + observability)
│   ├── connected/
│   └── airgapped/
├── operator/
│   ├── base/
│   ├── components/
│   │   └── manual-approval/     # Manual InstallPlan (airgapped only)
│   └── overlays/
│       ├── airgapped/
│       └── connected/
├── instance/
│   ├── base/
│   ├── components/
│   │   └── ha-availability/     # Optional availabilityConfig: High
│   └── overlays/
│       ├── airgapped/
│       └── connected/
├── observability/
│   ├── base/
│   ├── components/
│   │   └── odf-storage-sizes/   # Optional PVC size overrides
│   └── overlays/
│       ├── airgapped/
│       └── connected/
├── deploy-rhacm.yaml                   # Ansible staged full deploy (checks S4)
├── update-rhacm-values.sh              # air-gapped
├── update-rhacm-values-connected.sh    # connected
└── .gitignore
```

Base manifests use `patch-me-see-overlays-dir` placeholders. Overlays supply the
real catalog, channel, and ose-cli image.

## Upgrade notes

- **Air-gapped:** approve InstallPlans deliberately after mirroring the target ACM version.
- **Connected:** InstallPlans approve automatically; still validate channel before upgrading.
- Re-running observability apply is safe: the setup Job is idempotent. If the
  Job already completed, delete it before re-apply (`oc delete job observability-setup -n open-cluster-management-observability`) so the new Job can run.
- If you previously deployed the old ClusterRole-based setup SA (`cli-job-sa`),
  remove leftover cluster RBAC after migrating:

```bash
oc delete clusterrole acm-cli-job-sa-role --ignore-not-found
oc delete clusterrolebinding acm-gitops-rolebinding --ignore-not-found
```

## Troubleshooting

- **Operator not installing**: Verify catalog source, channel, and InstallPlan approval
- **MultiClusterHub not ready**: Confirm MCE subscription annotation catalog source matches the mirrored catalog
- **Observability Job failing**: Confirm S4 is Running in `s4`, `s4-credentials` exists, bucket API is reachable at `http://s4.s4.svc:5000/api`, and the ose-cli image is pullable from infra nodes
- **Pods on workers**: Confirm Subscription `spec.config`, MultiClusterHub
  `spec` + MCE annotation `config`, MultiClusterObservability, and the setup Job
  all set infra `nodeSelector` and tolerations (no namespace scheduler annotations)
