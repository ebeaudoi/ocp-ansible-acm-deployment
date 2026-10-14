# High availability MultiClusterHub

Sets `spec.availabilityConfig: High` for multi-replica hub components.
Not included by default (airgapped uses Basic). Add to an overlay:

```yaml
components:
  - ../../components/ha-availability
```
