#!/usr/bin/env bash
# latest-release.sh MAJOR
#
# Prints "CHART_VERSION APP_VERSION PLUGIN_HUB_VERSION" for the newest
# OpenEverest chart released on the MAJOR line, pre-releases included.
# PLUGIN_HUB_VERSION is the plugin-hub packaged into that chart, or "none"
# if it bundles none. It is read from the released package: releases resolve
# the dependency range when they package the chart, so the Chart.lock in git
# may name an older one.

set -euo pipefail

MAJOR="${1:?usage: $0 MAJOR}"
REPO_URL="${OPENEVEREST_CHART_REPO:-https://openeverest.github.io/helm-charts/}"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
export HELM_REPOSITORY_CONFIG="${work}/repositories.yaml"
export HELM_REPOSITORY_CACHE="${work}/cache"

helm repo add openeverest "${REPO_URL}" >/dev/null
read -r chart app < <(
  helm search repo openeverest/openeverest --devel --versions \
    --version ">=${MAJOR}.0.0-0, <$((MAJOR + 1)).0.0-0" -o json |
    jq -r 'first | "\(.version) \(.app_version)"'
)
if [[ -z "${chart}" || "${chart}" == "null" ]]; then
  echo "error: no openeverest chart released on the ${MAJOR}.x line" >&2
  exit 1
fi

helm pull openeverest/openeverest --version "${chart}" -d "${work}" >/dev/null
# helm package unpacks dependencies into charts/<name>/.
hub=$( (tar -xzOf "${work}/openeverest-${chart}.tgz" openeverest/charts/plugin-hub/Chart.yaml 2>/dev/null || true) |
  yq eval '.version // ""' -)
echo "${chart} ${app} ${hub:-none}"
