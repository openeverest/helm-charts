#!/bin/bash
# sync-controller-deployment.sh
#
# Fetches the controller manager deployment from the openeverest repo via
# kustomize (same pattern as sync-controller-rbac.sh) and transforms it into
# a Helm template for the everest-controller component.
#
# Syncs:
#   config/default kustomize build -> templates/everest-controller/deployment.yaml
#
# Usage:
#   OPENEVEREST_REPO_URL=https://github.com/openeverest/openeverest \
#   OPENEVEREST_VERSION=v2 \
#   OUTPUT_DIR=templates/everest-controller \
#     ./scripts/sync-controller-deployment.sh

set -euo pipefail

OPENEVEREST_REPO_URL="${OPENEVEREST_REPO_URL:?OPENEVEREST_REPO_URL is required}"
OPENEVEREST_VERSION="${OPENEVEREST_VERSION:?OPENEVEREST_VERSION is required}"
OUTPUT_DIR="${OUTPUT_DIR:?OUTPUT_DIR is required}"
KUSTOMIZE_IMAGE="${KUSTOMIZE_IMAGE:-registry.k8s.io/kustomize/kustomize:v5.7.0}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "${OUTPUT_DIR}"

DEST="${OUTPUT_DIR}/deployment.yaml"

echo "Fetching controller deployment from ${OPENEVEREST_REPO_URL}/config/default?ref=${OPENEVEREST_VERSION}..."

# Fetch all manifests via kustomize (same Docker pattern as sync-controller-rbac.sh).
docker run --rm \
  -v "${TMPDIR}":/workspace \
  -w /workspace \
  "${KUSTOMIZE_IMAGE}" \
  build "${OPENEVEREST_REPO_URL}/config/default?ref=${OPENEVEREST_VERSION}" \
  --output /workspace/

# Locate the deployment file kustomize emits.
deployment_file=$(find "${TMPDIR}" -name "*_deployment_openeverest-controller-manager.yaml" -type f 2>/dev/null | head -1)

if [ -z "${deployment_file}" ]; then
  echo "ERROR: Deployment manifest not found in kustomize output." >&2
  exit 1
fi

echo "Found deployment: ${deployment_file}"

# -------------------------------------------------------------------------
# Transform kustomize output into a Helm template.
#
# kustomize applies namePrefix=openeverest- and namespace=openeverest-system.
# We rename resources and apply Helm templating for image, args, resources,
# env, and serviceAccountName. Fields already correct in upstream (probes,
# security context, strategy, ports) pass through unchanged.
# -------------------------------------------------------------------------
{
  echo '{{- if .Values.controller.enabled }}'
  echo '# This file is auto-generated from the openeverest repo'"'"'s config/default/ via kustomize.'
  echo '# Do not edit manually. Run: make controller-deployment-gen'
  sed \
    -e '/app\.kubernetes\.io\/name: openeverest/d' \
    -e '/app\.kubernetes\.io\/managed-by: kustomize/d' \
    -e 's|name: openeverest-controller-manager|name: everest-controller|' \
    -e 's|namespace: openeverest-system|namespace: {{ include "everest.namespace" . }}|' \
    -e 's|serviceAccountName: openeverest-controller-manager|serviceAccountName: everest-controller-manager|' \
    -e 's|control-plane: controller-manager|app: everest-controller|g' \
    -e 's|app\.kubernetes\.io/name: openeverest|app: everest-controller|g' \
    -e 's|image: controller:latest|image: {{ (default .Values.server.image .Values.controller.image) }}:{{ .Chart.AppVersion }}|' \
    -e 's|- /everest-controller|- {{ .Values.controller.command }}|' \
    -e 's|"ALL"|ALL|' \
    -e 's|--monitoring-namespace=everest-monitoring|--monitoring-namespace={{ .Values.monitoring.namespaceOverride }}|' \
    -e 's|name: webhook-certs|name: everest-controller-webhook-server-cert|g' \
    -e 's|secretName: webhook-server-cert|secretName: everest-controller-webhook-server-cert|g' \
    "${deployment_file}" \
  | awk '
    BEGIN { in_resources = 0; in_args = 0 }

    # Template args — replace hardcoded values with Helm references.
    /^        - --metrics-bind-address=/ {
      print "        - --metrics-bind-address={{ .Values.controller.metricsBindAddress }}"
      next
    }
    /^        - --leader-elect$/ {
      print "        {{- if .Values.controller.leaderElection.enabled }}"
      print "        - --leader-elect"
      print "        {{- end }}"
      next
    }
    /^        - --health-probe-bind-address=/ {
      print "        - --health-probe-bind-address={{ .Values.controller.healthProbeBindAddress }}"
      next
    }

    # Replace env: [] with Helm env template.
    /^        env: \[\]$/ {
      print "        {{- if .Values.controller.env }}"
      print "        env:"
      print "        {{- toYaml .Values.controller.env | nindent 8 }}"
      print "        {{- end }}"
      next
    }

    # Replace resources block with Helm template.
    /^        resources:$/ {
      print "        resources: {{ toYaml .Values.controller.resources | nindent 10 }}"
      in_resources = 1; next
    }
    in_resources {
      if ($0 ~ /^          /) next
      in_resources = 0
    }

    # Default: pass through.
    { print }
  '
  echo '{{- end }}'
} > "${DEST}"

echo ""
echo "Deployment sync complete. File written to ${DEST}."
