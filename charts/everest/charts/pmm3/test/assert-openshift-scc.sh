#!/usr/bin/env bash
# Asserts that the pmm3 wrapper chart overrides the upstream PMM security
# context for OpenShift compatibility.
#
# Verifies the rendered StatefulSet:
#   - does NOT hardcode runAsUser / runAsGroup / fsGroup (SCC-rejected on OCP)
#   - sets runAsNonRoot: true
#   - sets seccompProfile.type: RuntimeDefault
#   - container drops ALL capabilities and disables privilege escalation
#
# Uses only python3 stdlib (no PyYAML) so it runs on a stock GitHub runner.
# Run via: `make -C charts/everest test-pmm3`
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM="${HELM:-helm}"

manifest="$("$HELM" template test "$CHART_DIR" --namespace pmm)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

which python3 >/dev/null 2>&1 || fail "python3 is required to run this test"

export manifest
python3 - <<'PY'
import os, re, sys

manifest = os.environ["manifest"]

# Split rendered manifest into YAML documents and keep the StatefulSet one.
docs = re.split(r"(?m)^---\s*$", manifest)
statefulsets = [
    d for d in docs
    if re.search(r"(?m)^kind:\s*StatefulSet\s*$", d)
]
if not statefulsets:
    sys.stderr.write("FAIL: no StatefulSet rendered\n")
    sys.exit(1)
sts = statefulsets[0]

# Pod securityContext lives immediately under spec.template.spec at 6-space indent:
#       securityContext:
#         <2 extra spaces for its children>
m = re.search(
    r"(?m)^      securityContext:\n((?:^        .+\n|^$\n)+)",
    sts,
)
if not m:
    sys.stderr.write("FAIL: no pod securityContext block in StatefulSet\n")
    sys.exit(1)
block = m.group(1)

# Hardcoded UIDs must be absent or null so OpenShift SCC can assign them.
for key in ("runAsUser", "runAsGroup", "fsGroup"):
    present = re.search(rf"(?m)^        {re.escape(key)}:\s*(.*)$", block)
    if not present:
        continue
    val = present.group(1).strip()
    if val and val.lower() != "null":
        sys.stderr.write(
            f"FAIL: pod securityContext.{key} is set to '{val}'; "
            "must be absent/null for OpenShift SCC\n"
        )
        sys.exit(1)

# runtime hardening must be set.
if not re.search(r"(?m)^        runAsNonRoot:\s*true\s*$", block):
    sys.stderr.write("FAIL: pod securityContext.runAsNonRoot must be true\n")
    sys.exit(1)

# seccompProfile.type: RuntimeDefault
if not re.search(r"(?m)^        seccompProfile:\n          type: RuntimeDefault\s*$", block):
    sys.stderr.write("FAIL: pod securityContext.seccompProfile.type must be RuntimeDefault\n")
    sys.exit(1)

# Container securityContext lives at 10-space indent under the container.
mc = re.search(
    r"(?m)^          securityContext:\n((?:^            .+\n|^              .+\n)+)",
    sts,
)
if not mc:
    sys.stderr.write("FAIL: no container securityContext block in StatefulSet\n")
    sys.exit(1)
cb = mc.group(1)

if "ALL" not in cb:
    sys.stderr.write("FAIL: container does not drop ALL capabilities\n")
    sys.exit(1)

if not re.search(r"(?m)^            allowPrivilegeEscalation:\s*false\s*$", cb):
    sys.stderr.write("FAIL: container.allowPrivilegeEscalation must be false\n")
    sys.exit(1)

print("OK: pmm3 OpenShift security context overrides render as expected")
PY
