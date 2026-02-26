VERSION ?= 0.0.0
.PHONY: release
release:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is not set."; \
		exit 1; \
	fi
	@for crd in templates/*.yaml; do \
		yq eval '.metadata.labels["everest.percona.com/version"] = "$(VERSION)"' $$crd -i; \
	done

EVEREST_OPERATOR_REPO_URL ?= https://github.com/openeverest/openeverest-operator
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
		build $(EVEREST_OPERATOR_REPO_URL)/$(CRD_DIR)?ref=$(CRD_VERSION) > $(CRD_SUBCHART_DIR)/$$crd_tmp_file --output templates;
	@crd_tmp_file="crd.tmp.yaml"; \
	docker run --rm \
		-v "$(CRD_SUBCHART_DIR)":/workspace \
		-w /workspace \
		registry.k8s.io/kustomize/kustomize:v5.7.0 \
		build $(OPENEVEREST_REPO_URL)/$(CRD_DIR)?ref=$(OPENEVEREST_CRD_VERSION) > $(CRD_SUBCHART_DIR)/$$crd_tmp_file --output templates;

	@bash $(CRD_SUBCHART_DIR)/scripts/labels.sh templates "everest.percona.com/crd=true,everest.percona.com/version=$(VERSION)";
