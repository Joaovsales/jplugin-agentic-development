# Spec: Flow node with a marker and no name

## System design

```flow
Scheduler -> Exporter : nightly
Exporter -> (new) : writes
```
