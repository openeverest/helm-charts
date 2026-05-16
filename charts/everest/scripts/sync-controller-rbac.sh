#!/bin/bash
# sync-controller-rbac.sh
#
# Fetches the controller RBAC manifests from the openeverest repo via kustomize
# and transforms them into Helm templates for the everest-controller component.
#
# Usage:
#   OPENEVEREST_REPO_URL=https://github.com/openeverest/openeverest \
#   OPENEVEREST_VERSION=v2 \
#   OUTPUT_DIR=templates/everest-controller \
#     ./scripts/sync-controller-rbac.sh
#
# This script is designed to be called by the helm-charts Makefile's
# `controller-manifests-gen` target, mirroring the `crds-gen` pattern.

set -euo pipefail

OPENEVEREST_REPO_URL="${OPENEVEREST_REPO_URL:?OPENEVEREST_REPO_URL is required}"
OPENEVEREST_VERSION="${OPENEVEREST_VERSION:?OPENEVEREST_VERSION is required}"
OUTPUT_DIR="${OUTPUT_DIR:?OUTPUT_DIR is required}"
KUSTOMIZE_IMAGE="${KUSTOMIZE_IMAGE:-registry.k8s.io/kustomize/kustomize:v5.7.0}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Fetching controller RBAC from ${OPENEVEREST_REPO_URL}/config/rbac?ref=${OPENEVEREST_VERSION}..."

# Fetch the raw RBAC manifests via kustomize (same Docker pattern as crds-gen).
docker run --rm \
  -v "${TMPDIR}":/workspace \
  -w /workspace \
  "${KUSTOMIZE_IMAGE}" \
  build "${OPENEVEREST_REPO_URL}/config/rbac?ref=${OPENEVEREST_VERSION}" \
  --output /workspace/

echo "Fetched manifests to temp dir:"
ls -la "${TMPDIR}"

# --- Transform each manifest into a Helm template ---
# The kustomize output produces individual YAML files with naming like:
#   rbac.authorization.k8s.io_v1_clusterrole_manager-role.yaml
# We parse each and write corresponding Helm templates.

# Map of kustomize output names -> helm template filenames.
# We only sync specific files to avoid overwriting hand-crafted templates.

sync_file() {
  local src_pattern="$1"
  local dest_name="$2"
  local helm_guard_start='{{- if .Values.controller.enabled }}'
  local helm_guard_end='{{- end }}'

  local src_file
  src_file=$(find "${TMPDIR}" -name "${src_pattern}" -type f 2>/dev/null | head -1)

  if [ -z "$src_file" ]; then
    echo "WARNING: No file matching '${src_pattern}' found in kustomize output. Skipping ${dest_name}."
    return
  fi

  local dest="${OUTPUT_DIR}/${dest_name}"
  echo "Syncing ${src_file} -> ${dest}"

  {
    echo "${helm_guard_start}"
    echo "# This file is auto-generated from the openeverest repo's config/rbac/ via kustomize."
    echo "# Do not edit manually. Run: make controller-manifests-gen"
    # Replace the hardcoded namespace 'system' and name prefix 'openeverest-' 
    # that kustomize applies from config/default/kustomization.yaml.
    # The raw role.yaml from config/rbac doesn't have these, but the kustomize 
    # build of config/rbac applies namePrefix and namespace from the kustomization.
    # Since we build config/rbac directly (not config/default), we get raw names.
    # We prefix names with 'everest-controller-' for Helm and template the namespace.
    sed \
      -e 's/name: manager-role/name: everest-controller-manager-role/' \
      -e 's/name: manager-rolebinding/name: everest-controller-manager-rolebinding/' \
      -e 's/name: controller-manager/name: everest-controller-manager/' \
      -e 's/name: leader-election-role$/name: everest-controller-leader-election-role/' \
      -e 's/name: leader-election-role-binding$/name: everest-controller-leader-election-rolebinding/' \
      -e 's/name: metrics-auth-role$/name: everest-controller-metrics-auth-role/' \
      -e 's/name: metrics-auth-rolebinding$/name: everest-controller-metrics-auth-rolebinding/' \
      -e 's/name: metrics-reader$/name: everest-controller-metrics-reader/' \
      -e "s/namespace: system/namespace: {{ include \"everest.namespace\" . }}/" \
      "$src_file"
    echo "${helm_guard_end}"
  } > "${dest}"
}

# Sync the manager ClusterRole (the main RBAC rules generated from kubebuilder markers).
sync_file "*_clusterrole_manager-role.yaml" "clusterrole.yaml"

# Sync the manager ClusterRoleBinding.
sync_file "*_clusterrolebinding_manager-rolebinding.yaml" "clusterrolebinding.yaml"

# Sync the leader election Role.
sync_file "*_role_leader-election-role.yaml" "leaderelection.role.yaml"

# Sync the leader election RoleBinding.
sync_file "*_rolebinding_leader-election-role-binding.yaml" "leaderelection.rolebinding.yaml"

# Sync the ServiceAccount.
sync_file "*_serviceaccount_controller-manager.yaml" "serviceaccount.yaml"

echo ""
echo "Controller RBAC sync complete. Files written to ${OUTPUT_DIR}/."
echo "Note: deployment.yaml is synced separately via the controller-deployment-gen target."
