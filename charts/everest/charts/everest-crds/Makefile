VERSION ?= 0.0.0
# The core release these CRDs belong to. templates/check-crd.yaml in the parent
# chart compares it with the chart's appVersion on upgrade.
VERSION_LABEL := openeverest.io/version
.PHONY: release
release:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is not set."; \
		exit 1; \
	fi
	@for crd in templates/*.yaml; do \
		yq eval '.metadata.labels["$(VERSION_LABEL)"] = "$(VERSION)"' $$crd -i; \
	done

# Argo CD applies lower sync waves first and stops at a wave that fails.
# Extensions put the objects OpenEverest checks against the compatibility
# window stamped on these CRDs at wave -1, so the CRDs, and the window they
# carry, are applied one wave earlier. Helm and Flux ignore the annotation.
SYNC_WAVE_ANNOTATION := argocd.argoproj.io/sync-wave
CRD_SYNC_WAVE := -2

OPENEVEREST_REPO_URL ?= https://github.com/openeverest/openeverest
CRD_DIR ?= config/crd
CRD_VERSION ?= main
# FIXME: this is temporary until we have a split between v1 and v2
OPENEVEREST_CRD_VERSION ?= v2
CRD_SUBCHART_DIR ?= $(PWD)
.PHONY: crds-gen
crds-gen:
	@crd_tmp_file="crd.tmp.yaml"; \
	docker run --rm \
		-v "$(CRD_SUBCHART_DIR)":/workspace \
		-w /workspace \
		registry.k8s.io/kustomize/kustomize:v5.7.0 \
		build $(OPENEVEREST_REPO_URL)/$(CRD_DIR)?ref=$(OPENEVEREST_CRD_VERSION) > $(CRD_SUBCHART_DIR)/$$crd_tmp_file --output templates;

	@bash $(CRD_SUBCHART_DIR)/scripts/labels.sh templates "everest.percona.com/crd=true,$(VERSION_LABEL)=$(VERSION)";
	@for crd in templates/*.yaml; do \
		yq eval '.metadata.annotations["$(SYNC_WAVE_ANNOTATION)"] = "$(CRD_SYNC_WAVE)"' $$crd -i; \
	done
