# OpenShift GitOps Components

Composable patches applied on top of the default OpenShift GitOps (Argo CD) instance.

**Active vs library:** components listed under `components:` in
`instance/overlays/connected/kustomization.yaml` are applied by `deploy.yaml`.
Other components in this directory are an optional library — add them to the
overlay when you need them; they are not deleted and are safe to ignore.

## Available components

* [annotation-resource-tracking](annotation-resource-tracking)
* [application-controller-cluster-admin](application-controller-cluster-admin)
* [edge-termination](edge-termination)
* [enable-notifications](enable-notifications)
* [gitops-admins](gitops-admins)
* [health-check-odf](health-check-odf)
* [health-check-olm](health-check-olm)
* [health-check-openshift-builds](health-check-openshift-builds)
* [kustomize-build-enable-helm](kustomize-build-enable-helm)

## Usage

Add a `components` section to your overlay `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

components:
  - ../../components/annotation-resource-tracking
  - ../../components/kustomize-build-enable-helm
```
