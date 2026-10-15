# GitOps Operator

Deploy and manage the OpenShift GitOps operator (ArgoCD) in air-gapped environments using Kustomize.

## Prerequisites

- **OpenShift CLI (`oc`)**: Version 4.x or later
- **Cluster Access**: Admin access to the OpenShift cluster
- **Air-Gapped Environment**: Access to internal registry with GitOps operator images
- **Catalog Source**: Red Hat catalog source configured in the cluster
- **Infrastructure Nodes**: GitOps operator should be deployed on infrastructure nodes

## Update Script

The **`update-gitops-values.sh`** script automates the update of GitOps operator configuration files.

### Usage

1. **Edit the script** to set your values:

```bash
cd gitops
vim update-gitops-values.sh
```

2. **Update the variables**:

```bash
GITOPS_SUBSCRIPTION_CHANNEL="latest"
GITOPS_CATALOG_SOURCE="your-redhat-catalog"
# GITOPS_GIT_USER="admin"  # Uncomment if needed
```

3. **Run the script**:

```bash
./update-gitops-values.sh
```

The script will:
- Create timestamped backups of all kustomization files
- Update operator subscription channel and catalog source
- Display a summary of all changes

## Deployment Steps

### 1. Deploy GitOps Operator

```bash
oc apply -k operator/overlays/infra/
```

### 2. Monitor Operator Installation

```bash
oc get pods -w -n openshift-gitops-operator
```

Wait for all operator pods to be in `Running` state.

### 3. Deploy GitOps Instance (Optional)

```bash
oc apply -k example-instance/overlays/airgapped/
```

### 4. Verify Deployment

```bash
# Check operator status
oc get csv -n openshift-gitops-operator

# Check default ArgoCD instance
oc get pods -n openshift-gitops

# Access ArgoCD console
oc get route -n openshift-gitops
```

## Directory Structure

```
gitops/
├── operator/
│   ├── base/                    # Base operator configuration
│   │   ├── subscription.yaml
│   │   └── kustomization.yaml
│   ├── components/              # Operator components
│   │   └── openshift-gitops-operator/
│   └── overlays/
│       └── infra/               # Infrastructure node overlay
│           └── kustomization.yaml
├── example-instance/
│   ├── base/                    # Base GitOps instance
│   ├── components/              # Instance components
│   └── overlays/
│       └── airgapped/           # Air-gapped instance overlay
│           └── kustomization.yaml
└── update-gitops-values.sh     # Configuration update script
```

## Troubleshooting

- **Operator not installing**: Verify catalog source is accessible and channel exists
- **ArgoCD not accessible**: Check route configuration and network policies
- **Git repository access**: Ensure Git repositories are accessible from the cluster

