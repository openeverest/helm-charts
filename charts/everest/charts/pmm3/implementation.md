# PMM3 OpenShift Security Context

## Background

- Issue: openeverest/helm-charts#70 — PMM3 deploys fail on OpenShift.
- The upstream `percona/pmm` chart (v1.4.14) hardcodes `runAsUser`,
  `runAsGroup` and `fsGroup` to `1000` in `podSecurityContext`.
  OpenShift's restricted SCC rejects any pod that pins a UID outside the
  namespace's assigned range, so the StatefulSet never schedules.
- The wrapper (`charts/everest/charts/pmm3`) already nullifies those UIDs
  (see commit `91830b5`) so OpenShift can assign a random UID instead.

## Why test this

The wrapper depends on values reaching the subchart through the `pmm.*`
key. If the dependency bumps or the override is accidentally dropped, the
hardcoded `1000` returns and OpenShift breaks again — silently, until
someone tries to install there. A template-level assertion catches that
regression in CI instead of in the field.

## What the test checks

`charts/everest/charts/pmm3/test/assert-openshift-scc.sh` renders the
wrapper chart and asserts the resulting StatefulSet:

- `runAsUser`, `runAsGroup`, `fsGroup` are absent or null on the pod
  security context.
- `runAsNonRoot: true` and `seccompProfile.type: RuntimeDefault` are set.
- The container drops `ALL` capabilities and sets
  `allowPrivilegeEscalation: false`.

It uses only `bash` + `python3` stdlib (no PyYAML), so it runs on a stock
GitHub Actions runner. It is wired into `make test` via the new
`test-pmm3` Makefile target.

## What is not covered here

Whether PMM actually starts without `runAsUser: 0` — the container writes
to `/srv` (the PVC mount); if files are root-owned the random non-root UID
may hit permission errors at startup. That is a runtime question and needs
a real OpenShift cluster (e.g. CRC) to answer. The template test only
protects the manifest contract, not the runtime behaviour.
