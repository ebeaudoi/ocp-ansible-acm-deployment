# ODF storage size overrides

JSON6902 patches for MultiClusterObservability PVC sizes. Edit the values in
`kustomization.yaml`, then enable the component from an overlay:

```yaml
components:
  - ../../components/odf-storage-sizes
```

Requires OpenShift Data Foundation (NooBaa for the ObjectBucketClaim and Ceph RBD
for the `ocs-storagecluster-ceph-rbd` storage class).
