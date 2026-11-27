#!/bin/bash
# annotate-chart.sh
#
# Records in Chart.yaml which OpenEverest release the chart ships and what that
# release is compatible with, so that tools can read both from the chart
# metadata alone (Helm repository index, OCI config blob) without rendering it:
#
#   openeverest.io/version               the release (VERSION)
#   openeverest.io/min-contract-version  the extension builds the release
#   openeverest.io/contract-version        accepts, from min to current
#   openeverest.io/upgradable-from       the releases it upgrades in place;
#                                          empty: fresh installs only
#
# OpenEverest stamps the last three on every CRD it builds, and the CRDs reach
# this chart through `make crds-gen`. CRDs synced from an OpenEverest that does
# not stamp them yet carry none: the chart then gets no window annotations,
# only a warning.
#
# Usage:
#   CHART_FILE=Chart.yaml \
#   CRD_DIR=charts/everest-crds/templates \
#   VERSION=2.0.0 \
#     ./scripts/annotate-chart.sh
#
# This script is designed to be called by the helm-charts Makefile's
# `annotate-chart` target, which `prepare-chart` runs on every release.

set -euo pipefail

CHART_FILE="${CHART_FILE:?CHART_FILE is required}"
CRD_DIR="${CRD_DIR:?CRD_DIR is required}"
VERSION="${VERSION:?VERSION is required}"

VERSION_KEY="openeverest.io/version"
WINDOW_KEYS=(
  "openeverest.io/contract-version"
  "openeverest.io/min-contract-version"
  "openeverest.io/upgradable-from"
)

# SemVer 2.0.0 (https://semver.org) as a POSIX extended regular expression.
NUM='(0|[1-9][0-9]*)'
PRE='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
SEMVER="^${NUM}\.${NUM}\.${NUM}(-${PRE}(\.${PRE})*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"

die() {
  echo "error: $*" >&2
  exit 1
}

warn() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::warning::$*"
  else
    echo "warning: $*" >&2
  fi
}

is_semver() {
  [[ "$1" =~ $SEMVER ]]
}

# upgradable-from is a comma-separated list of core releases; empty means the
# release supports fresh installs only.
is_semver_list() {
  local item items
  [[ -z "$1" ]] && return 0
  [[ "$1" == *, ]] && return 1
  IFS=',' read -ra items <<< "$1"
  for item in "${items[@]}"; do
    is_semver "${item}" || return 1
  done
}

set_annotation() {
  K="$1" V="$2" yq eval -i '.annotations[strenv(K)] = (strenv(V) | . style="double")' "${CHART_FILE}"
}

delete_annotation() {
  K="$1" yq eval -i 'del(.annotations[strenv(K)])' "${CHART_FILE}"
}

[[ -f "${CHART_FILE}" ]] || die "${CHART_FILE} not found"
is_semver "${VERSION}" || die "VERSION ${VERSION} is not a SemVer 2.0.0 version"

shopt -s nullglob
crds=("${CRD_DIR}"/*.yaml)
(( ${#crds[@]} > 0 )) || die "no CRDs found in ${CRD_DIR}"

# A single core build stamps the same values on every CRD, so CRDs that
# disagree, or that carry only part of the window, were synced from different
# core builds. Fail instead of picking a value: any choice would describe a
# core that this chart does not ship.
declare -A window=()
absent=0
for key in "${WINDOW_KEYS[@]}"; do
  # One line per CRD: its name, then whether it carries the annotation and the
  # JSON-encoded value, so that an absent annotation and an empty one differ.
  report=$(KEY="${key}" yq eval -N '
    .metadata.name + " " +
    ((.metadata.annotations // {}) | has(strenv(KEY)) | tostring) + ":" +
    ((.metadata.annotations[strenv(KEY)] // "") | @json)
  ' "${crds[@]}")
  states=$(cut -d' ' -f2- <<< "${report}" | sort -u)
  if [[ $(wc -l <<< "${states}") -ne 1 ]]; then
    die "the CRDs in ${CRD_DIR} disagree on ${key}; sync them from a single OpenEverest build:"$'\n'"${report}"
  fi
  case "${states}" in
    false:*)
      absent=$((absent + 1))
      ;;
    true:\"*\")
      value="${states#true:\"}"
      window["${key}"]="${value%\"}"
      ;;
    *)
      die "cannot read ${key} from the CRDs in ${CRD_DIR}: ${states}"
      ;;
  esac
done

if (( absent > 0 && absent < ${#WINDOW_KEYS[@]} )); then
  die "the CRDs in ${CRD_DIR} carry only part of the compatibility window; expected all of ${WINDOW_KEYS[*]}"
fi
if (( absent == 0 )); then
  # Only the format is checked here: core's generator already refuses a
  # minimum above the current version before it stamps the CRDs.
  for key in "openeverest.io/contract-version" "openeverest.io/min-contract-version"; do
    is_semver "${window[${key}]}" || die "${key} \"${window[${key}]}\" is not a SemVer 2.0.0 version"
  done
  key="openeverest.io/upgradable-from"
  is_semver_list "${window[${key}]}" || die "${key} \"${window[${key}]}\" is not a comma-separated list of SemVer 2.0.0 versions"
fi

set_annotation "${VERSION_KEY}" "${VERSION}"
echo "${VERSION_KEY}: ${VERSION}"

if (( absent > 0 )); then
  warn "the CRDs in ${CRD_DIR} carry no compatibility window (${WINDOW_KEYS[*]}); ${CHART_FILE} gets none either"
  # Drop a window left by an earlier run, so the chart never claims one its
  # CRDs do not carry.
  for key in "${WINDOW_KEYS[@]}"; do
    delete_annotation "${key}"
  done
  exit 0
fi

for key in "${WINDOW_KEYS[@]}"; do
  set_annotation "${key}" "${window[${key}]}"
  echo "${key}: ${window[${key}]}"
done
