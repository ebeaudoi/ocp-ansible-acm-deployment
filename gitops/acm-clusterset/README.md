Installing the "gitops" operator

- Example of creating an ACM governance installing gitops
  - https://role.rhu.redhat.com/rol/app/courses/do0015l-2.13/pages/ch01s04
  - https://github.com/ebeaudoi/deploy-ocp-operators/tree/main/gitops/acm-clusterset

- Create the gitops-configure project.
$ oc new-project gitops-configure

- Create a cluster set that groups all the clusters where the OpenShift GitOps operator must be installed.
  - Go to Infrastructure → Clusters, select the Cluster sets tab, and click Create cluster set.
  - Set the name of the cluster set to "gitops-configure" and click Create.

- Click Manage resource assignments. Select the two clusters, click Review, and click Save.

- Bind the new cluster set to the gitops-configure namespace by clicking Actions → Edit namespace bindings.
  - Select the gitops-configure namespace, and click Save.

- To install and configure the OpenShift GitOps operator, you use a governance policy. 
  - Review the policy-generator.yaml
~~~
$ ls -ltr
total 31944
-rw-r--r-- 1 admin admin      173 Jul 30 14:44 ca-bundle.yaml
-rw-r--r-- 1 admin admin      313 Jul 30 14:44 cluster-role-binding.yaml
-rw-r--r-- 1 admin admin      486 Jul 30 14:50 gitops-operator.yaml
-rw-r--r-- 1 admin admin      547 Jul 30 14:55 policy-generator.yaml
-rw-r--r-- 1 admin admin     1189 Jul 30 14:56 argocd-configuration.yaml


---
==============================
### argocd-configuration.yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  rbac:
    defaultPolicy: ""
    policy: |
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
      g, ocpadmins, role:admin
    scopes: '[groups]'
  repo:
    volumeMounts:
      - mountPath:
          /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
        subPath: ca-bundle.crt
        name: cluster-root-ca-bundle
    volumes:
      - configMap:
          name: cluster-root-ca-bundle
        name: cluster-root-ca-bundle
  applicationSet:
    resources:
      limits:
        cpu: "2"
        memory: 1Gi
      requests:
        cpu: 250m
        memory: 512Mi
    webhookServer:
      ingress:
        enabled: false
      route:
        enabled: false
  resourceExclusions: |
    - apiGroups:
      - tekton.dev
      clusters:
      - '*'
      kinds:
      - TaskRun
      - PipelineRun
  server:
    route:
      enabled: true
  sso:
    dex:
      openShiftOAuth: true
      resources:
        limits:
          cpu: 500m
          memory: 256Mi
        requests:
          cpu: 250m
          memory: 128Mi
    provider: dex
---
=========================
### ca-bundle.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: cluster-root-ca-bundle
  namespace: openshift-gitops
  labels:
    config.openshift.io/inject-trusted-cabundle: 'true'

---
===================
### cluster-role-binding.yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: argo-admin
subjects:
  - kind: ServiceAccount
    name: openshift-gitops-argocd-application-controller
    namespace: openshift-gitops
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin

---
========================
### gitops-operator.yaml
apiVersion: policy.open-cluster-management.io/v1beta1
kind: OperatorPolicy
metadata:
  name: install-gitops-operator
spec:
  remediationAction: enforce
  severity: critical
  complianceType: musthave
  subscription:
    name: openshift-gitops-operator
    namespace: openshift-gitops-operator
    channel: latest
    source: redhat-operators
    sourceNamespace: openshift-marketplace
    startingCSV: openshift-gitops-operator.v1.21.1
  upgradeApproval: Automatic
  versions: []


---
=========================
### policy-generator.yaml
apiVersion: policy.open-cluster-management.io/v1
kind: PolicyGenerator
metadata:
  name: gitops-policy-generator
policyDefaults:
  namespace: gitops-configure
  orderManifests: true
  consolidateManifests: false
  remediationAction: enforce
  placement:
    name: gitops-configure
    labelSelector:
      vendor: OpenShift
placementBindingDefaults:
  name: gitops-configure
policies:
  - name: gitops-configure
    manifests:
      - path: gitops-operator.yaml
      - path: cluster-role-binding.yaml
      - path: argocd-configuration.yaml

~~~  
  
- Apply the governance policy.
  - Run the PolicyGenerator command, and apply the resulting resources.
    $ PolicyGenerator policy-generator.yaml |  oc apply -f -  
  
- Switch to the RHACM web console for following the remediation process. Go to Governance and select the Policies tab. Wait for both clusters to be compliant, which takes up to five minutes.

- Import the clusters into Argo CD using the below yaml file
~~~
### gitops-register.yaml
---
apiVersion: cluster.open-cluster-management.io/v1beta2
kind: ManagedClusterSetBinding
metadata:
  name: gitops-configure
  namespace: openshift-gitops
spec:
  clusterSet: gitops-configure
---
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: Placement
metadata:
  name: gitops-configure
  namespace: openshift-gitops
spec:
  tolerations:
    - key: cluster.open-cluster-management.io/unreachable
      operator: Exists
    - key: cluster.open-cluster-management.io/unavailable
      operator: Exists
  clusterSets:
    - gitops-configure
---
apiVersion: apps.open-cluster-management.io/v1beta1
kind: GitOpsCluster
metadata:
  name: gitops-configure
  namespace: openshift-gitops
spec:
  argoServer:
    argoNamespace: openshift-gitops
  placementRef:
    kind: Placement
    apiVersion: cluster.open-cluster-management.io/v1beta1
    name: gitops-configure
    namespace: openshift-gitops
~~~

- Import the cluster by applying the gitops-register.yaml resource file.
  $ oc apply -f gitops-register.yaml

