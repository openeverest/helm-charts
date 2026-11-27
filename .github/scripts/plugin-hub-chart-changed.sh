#!/usr/bin/env bash
# plugin-hub-chart-changed.sh OLD NEW
#
# Prints "true" when the plugin-hub chart changed between versions OLD and NEW
# beyond its own version and image, and "false" otherwise. The diff goes to
# stderr.
#
# plugin-hub's release workflow rewrites Chart.yaml's version and appVersion
# and the image repository and tag in values.yaml; those, and comments in both
# files, are normalised away.
# An image-only release needs no OpenEverest chart release: plugin-hub updates
# its own image in place. Anything else (templates, other values, Chart.yaml
# annotations or dependencies) does.

set -euo pipefail

OLD="${1:?usage: $0 OLD NEW}"
NEW="${2:?usage: $0 OLD NEW}"
CHART_REF="${PLUGIN_HUB_CHART:-oci://ghcr.io/openeverest/charts/plugin-hub}"

if [[ "${OLD}" == "${NEW}" ]]; then
  echo false
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

for v in "${OLD}" "${NEW}"; do
  mkdir -p "${work}/${v}"
  helm pull "${CHART_REF}" --version "${v}" --untar --untardir "${work}/${v}" >/dev/null
  chart="${work}/${v}/plugin-hub"
  # Compare Chart.yaml and values.yaml as data, so that comments don't count.
  yq eval -i 'del(.version) | del(.appVersion) | ... comments=""' "${chart}/Chart.yaml"
  yq eval -i '.image.repository = "IMAGE" | .image.tag = "TAG" | ... comments=""' "${chart}/values.yaml"
  # Documentation only.
  rm -f "${chart}/README.md"
done

if (cd "${work}" && diff -ru "${OLD}/plugin-hub" "${NEW}/plugin-hub") >&2; then
  echo false
else
  echo true
fi
