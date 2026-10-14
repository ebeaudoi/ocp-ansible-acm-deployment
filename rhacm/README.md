# Red Hat Advanced Cluster Management (RHACM)

Deploy RHACM operator, MultiClusterHub, and optional observability in air-gapped
environments using Kustomize.

## Prerequisites

- **OpenShift CLI (`oc`)**: Version 4.x or later
- **Cluster Access**: Admin access to the OpenShift cluster
- **Catalog Source**: Mirrored Red Hat catalog available in the cluster
- **Infrastructure Nodes**: Workloads target `node-role.kubernetes.io/infra`
  via explicit `nodeSelector`/`tolerations` on Subscription, MultiClusterHub
  (including MCE `mce-subscription-spec` config), MultiClusterObservability, and
  the observability setup Job. Namespaces do **not** use
  `openshift.io/node-selector` or `scheduler.alpha.kubernetes.io/defaultTolerations`.
- **ODF (observability only)**: OpenShift Data Foundation with NooBaa and the
  `ocs-storagecluster-ceph-rbd` storage class

## Update Script

`update-rhacm-values.sh` updates environment-specific values in the airgapped
overlays. Timestamped backups are written beside each overlay and ignored via
`.gitignore`.

1. Edit the variables at the top of the script:

```bash
cd rhacm
vim update-rhacm-values.sh
```

```bash
RHACM_SUBSCRIPTION_CHANNEL="release-2.12"
RHACM_CATALOG_SOURCE="your-redhat-catalog"
# Prefer your internal registry mirror for air-gapped clusters
RHACM_OSE_CLI_IMAGE="registry.example.com/openshift4/ose-cli@sha256:..."
```

2. Run:

```bash
./update-rhacm-values.sh
```

## Deployment Steps

### 1. Deploy RHACM Operator

```bash
oc apply -k operator/overlays/airgapped/
```

The airgapped overlay sets `installPlanApproval: Manual`. Approve the InstallPlan
when ready:

```bash
oc get installplan -n open-cluster-management
oc patch installplan <name> -n open-cluster-management \
  --type merge -p '{"spec":{"approved":true}}'
```

### 2. Wait for the operator CSV

```bash
oc wait csv -n open-cluster-management \
  -l operators.coreos.com/advanced-cluster-management.open-cluster-management \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
```

### 3. Deploy MultiClusterHub

```bash
oc apply -k instance/overlays/airgapped/
oc wait mch multiclusterhub -n open-cluster-management \
  --for=jsonpath='{.status.phase}'=Running --timeout=1200s
```

For multi-replica hub components, add the HA component to the instance overlay:

```yaml
components:
  - ../../components/ha-availability
```

### 4. Deploy Observability (Optional)

Requires ODF/NooBaa. Apply only after MultiClusterHub is Running.

```bash
oc apply -k observability/overlays/airgapped/
oc wait job/observability-setup -n open-cluster-management-observability \
  --for=condition=complete --timeout=600s
oc get mco observability
```

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
├── operator/
│   ├── base/
│   ├── components/
│   │   └── manual-approval/     # Manual InstallPlan (used by airgapped)
│   └── overlays/airgapped/
├── instance/
│   ├── base/
│   ├── components/
│   │   └── ha-availability/     # Optional availabilityConfig: High
│   └── overlays/airgapped/
├── observability/
│   ├── base/
│   ├── components/
│   │   └── odf-storage-sizes/   # Optional PVC size overrides
│   └── overlays/airgapped/
├── update-rhacm-values.sh
└── .gitignore
```

Base manifests use `patch-me-see-overlays-dir` placeholders. Overlays supply the
real catalog, channel, and ose-cli image.

## Upgrade notes

- Approve InstallPlans deliberately after mirroring the target ACM version.
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
- **Observability Job failing**: Confirm ODF/NooBaa is healthy and the ose-cli image is pullable from infra nodes
- **Pods on workers**: Confirm Subscription `spec.config`, MultiClusterHub
  `spec` + MCE annotation `config`, MultiClusterObservability, and the setup Job
  all set infra `nodeSelector` and tolerations (no namespace scheduler annotations)
