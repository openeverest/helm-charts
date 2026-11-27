#!/usr/bin/env bash
# next-chart-patch-version.sh CHART_VERSION APP_VERSION
#
# Prints the chart version of a chart-only patch release on top of a release
# with CHART_VERSION and APP_VERSION. The patch keeps APP_VERSION: it ships the
# same OpenEverest and only repackages the chart.
#
#   2.0.0-dev.4   2.0.0-dev.4 -> 2.0.0-dev.4.1
#   2.0.0-dev.4.1 2.0.0-dev.4 -> 2.0.0-dev.4.2
#
# Only pre-releases are supported: a chart-only patch of a stable X.Y.Z would
# take a version that sorts below it (X.Y.Z-N) or one the next core release
# needs (X.Y.Z+1). Exits 3 for a stable APP_VERSION so the caller can ask a
# maintainer to pick the chart version.

set -euo pipefail

CHART="${1:?usage: $0 CHART_VERSION APP_VERSION}"
APP="${2:?usage: $0 CHART_VERSION APP_VERSION}"

if [[ "${APP}" != *-* ]]; then
  echo "error: ${APP} is a stable release; pick the chart version of its chart-only patch by hand" >&2
  exit 3
fi
if [[ "${APP}" == *+* || "${CHART}" == *+* ]]; then
  echo "error: build metadata is not supported: ${CHART} ${APP}" >&2
  exit 1
fi

if [[ "${CHART}" == "${APP}" ]]; then
  echo "${APP}.1"
elif [[ "${CHART}" =~ ^${APP//./\\.}\.([0-9]+)$ ]]; then
  echo "${APP}.$((BASH_REMATCH[1] + 1))"
else
  echo "error: chart ${CHART} is not ${APP} or a chart-only patch of it" >&2
  exit 1
fi
