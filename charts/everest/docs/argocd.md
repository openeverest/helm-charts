# Using OpenEverest Helm Chart with ArgoCD

## Overview
Everest can be installed and managed using ArgoCD, but there are specific configurations you must apply to avoid common pitfalls.
This guide outlines these issues and provides recommended configurations.

## Known issues (and solutions)

* The chart contains resources whose values are randomly generated if not explicitly specified. 
Since ArgoCD rerenders templates on every sync, these values will change, leading to your Application always appearing out of sync.
To resolve this, you need to include these resources in the `spec.ignoreDifferences` fields (see example below).
* The `everest-accounts` Secret might be managed externally (e.g., via `everestctl`).
To prevent ArgoCD from overwriting changes applied externally, include this Secret in the `spec.ignoreDifferences` field.
* During chart upgrades, OpenEverest uses a `pre-upgrade` hook to verify some prerequisites.
ArgoCD treats this as a `PreSync` hook, causing upgrade checks to run on every sync, which will eventually fail.
To avoid this, disable the upgrade checks by setting `upgrade.preflightChecks=false`.
Note that disabling these checks means safe upgrades cannot be guaranteed when using ArgoCD.

#### Recommended configuration example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
...
spec:
  ...
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - RespectIgnoreDifferences=true
    # To prevent issues with synchronising some CRDs.
    - ServerSideApply=true
  ...
  ignoreDifferences:
  # If `server.jwtKey` is not set, the chart will generates a random key.
  # As a result, the Secret will always be out of sync, since ArgoCD will
  # rerender it on each sync.
  - group: ""
    jsonPointers:
    - /data
    kind: Secret
    name: everest-jwt
    namespace: everest-system
  # If `server.initialAdminPassword` is not set, the chart will generates a random password.
  # As a result, the Secret will always be out of sync, since ArgoCD will
  # rerender it on each sync. Moreover, this Secret may be managed externally, for example, using `everestctl`.
  - group: ""
    jsonPointers:
    - /data
    kind: Secret
    name: everest-accounts
    namespace: everest-system
  ...
  source:
    helm:
      parameters:
      - name: upgrade.preflightChecks
        value: "false"
...
```

Complete example can be found [here](./application.yaml).
