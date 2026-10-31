#!/bin/bash
# sync-backupstorageclasses.sh
#
# Fetches the built-in BackupStorageClasses from the openeverest repo via
# kustomize and writes one Helm template per class.
#
# Usage:
#   OPENEVEREST_REPO_URL=https://github.com/openeverest/openeverest \
#   OPENEVEREST_VERSION=main \
#   OUTPUT_DIR=templates/backupstorageclasses \
#     ./scripts/sync-backupstorageclasses.sh
#
# This script is designed to be called by the helm-charts Makefile's
# `backupstorageclasses-gen` target, mirroring `controller-manifests-gen`.

set -euo pipefail

OPENEVEREST_REPO_URL="${OPENEVEREST_REPO_URL:?OPENEVEREST_REPO_URL is required}"
OPENEVEREST_VERSION="${OPENEVEREST_VERSION:?OPENEVEREST_VERSION is required}"
OUTPUT_DIR="${OUTPUT_DIR:?OUTPUT_DIR is required}"
KUSTOMIZE_IMAGE="${KUSTOMIZE_IMAGE:-registry.k8s.io/kustomize/kustomize:v5.7.0}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Fetching backup storage classes from ${OPENEVEREST_REPO_URL}/config/backupstorageclasses?ref=${OPENEVEREST_VERSION}..."

docker run --rm \
  -v "${TMPDIR}":/workspace \
  -w /workspace \
  "${KUSTOMIZE_IMAGE}" \
  build "${OPENEVEREST_REPO_URL}/config/backupstorageclasses?ref=${OPENEVEREST_VERSION}" \
  --output /workspace/

mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DIR}"/*.yaml

# kustomize names each file <group>_<version>_backupstorageclass_<name>.yaml.
for src in "${TMPDIR}"/*_backupstorageclass_*.yaml; do
  name="${src##*_backupstorageclass_}"
  dest="${OUTPUT_DIR}/${name}"
  echo "Syncing ${src} -> ${dest}"
  {
    echo "# This file is auto-generated from the openeverest repo's config/backupstorageclasses/ via kustomize."
    echo "# Do not edit manually. Run: make backupstorageclasses-gen"
    cat "${src}"
  } > "${dest}"
done

echo ""
echo "Backup storage class sync complete. Files written to ${OUTPUT_DIR}/."
