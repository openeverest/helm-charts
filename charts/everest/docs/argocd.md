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
* Unless `controller.webhook.certs` is set, the chart generates the controller's webhook certificate, and the CA that signs it, at render time.
It reuses the existing certificate on upgrade (`controller.webhook.preserveTLSCerts`) only through `lookup` and `.Release.IsUpgrade`, neither of which applies under `helm template`, which is how ArgoCD renders the chart.
So every sync writes a new certificate to the `everest-controller-webhook-server-cert` Secret and a new CA to the `caBundle` of each webhook in the `everest-controller-validating-webhook-configuration` ValidatingWebhookConfiguration.
The API server trusts the new CA at once, but the controller keeps serving the old certificate until the kubelet refreshes the mounted Secret, so creating a `Backup`, `BackupImport` or `Restore` fails for a minute or so after each sync (the webhooks use `failurePolicy: Fail`).
To avoid this, add both the Secret's `/data` and the webhooks' `caBundle` to `spec.ignoreDifferences`, and set the `RespectIgnoreDifferences=true` sync option: without it, `ignoreDifferences` only affects the diff and the sync still applies the newly rendered values.
Always ignore the two together. Ignoring only one of them leaves a `caBundle` that did not sign the served certificate, and the webhooks then reject every request.
If that has already happened, delete both the Secret and the ValidatingWebhookConfiguration and sync: ArgoCD recreates them from a single render, which is also how to rotate the certificate later.
The same applies to the server's certificate when `server.tls.enabled=true` and neither `server.tls.secret.certs` nor `server.tls.certificate.create` is set: every sync replaces the certificate in the `everest-server-tls` Secret (`server.tls.secret.name`), so ignore its `/data` too.
None of these entries is needed for certificates you supply through `controller.webhook.certs` or `server.tls.secret.certs`, or that cert-manager issues (`server.tls.certificate.create`).
* During chart upgrades, OpenEverest uses a `pre-upgrade` hook to verify some prerequisites.
ArgoCD treats this as a `PreSync` hook, causing upgrade checks to run on every sync, which will eventually fail.
To avoid this, disable the upgrade checks by setting `upgrade.preflightChecks=false`.
Note that disabling these checks means safe upgrades cannot be guaranteed when using ArgoCD.
* Deleting the Application runs a `PreDelete` hook that refuses the deletion while OpenEverest still protects objects in use (`MonitoringDestination`s, `BackupStorage`s and Secrets with its in-use finalizer); its Job's log lists them. Delete those objects, or their namespaces, first.
ArgoCD runs `PreDelete` hooks from version 3.3. Older versions skip the check, and deleting the Application then leaves those objects with a finalizer that nothing removes any more.

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
    # Keeps the sync from overwriting the fields in ignoreDifferences.
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
  # Unless `controller.webhook.certs` is set, the chart generates a new
  # webhook certificate and CA on each render. Ignore the Secret and the
  # webhooks' caBundle together, or they stop matching and the webhooks
  # reject every request. RespectIgnoreDifferences=true keeps the sync
  # from overwriting them.
  - group: ""
    jsonPointers:
    - /data
    kind: Secret
    name: everest-controller-webhook-server-cert
    namespace: everest-system
  - group: admissionregistration.k8s.io
    jqPathExpressions:
    - .webhooks[]?.clientConfig.caBundle
    kind: ValidatingWebhookConfiguration
    name: everest-controller-validating-webhook-configuration
  # If `server.tls.enabled=true` without `server.tls.secret.certs` or
  # `server.tls.certificate.create`, the chart generates a new self-signed
  # server certificate on each render.
  - group: ""
    jsonPointers:
    - /data
    kind: Secret
    name: everest-server-tls
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
