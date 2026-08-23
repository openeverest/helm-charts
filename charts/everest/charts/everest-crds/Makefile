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

OPENEVEREST_REPO_URL ?= https://github.com/openeverest/openeverest
CRD_DIR ?= config/crd
CRD_VERSION ?= main
OPENEVEREST_CRD_VERSION ?= main
CRD_SUBCHART_DIR ?= $(PWD)
.PHONY: crds-gen
crds-gen:
# Generate into a temporary directory and only swap it in once kustomize has
# succeeded, so a failed build cannot leave templates/ empty or half-written.
# The swap clears templates/ first: kustomize only writes the manifests it
# currently generates, so a CRD that upstream has dropped or renamed would
# otherwise linger here and still be labelled and shipped by the chart.
	@tmp_dir="$(CRD_SUBCHART_DIR)/.crds-gen.tmp"; \
	rm -rf "$$tmp_dir" && mkdir -p "$$tmp_dir" && \
	docker run --rm \
		-v "$(CRD_SUBCHART_DIR)":/workspace \
		-w /workspace \
		registry.k8s.io/kustomize/kustomize:v5.7.0 \
		build $(OPENEVEREST_REPO_URL)/$(CRD_DIR)?ref=$(OPENEVEREST_CRD_VERSION) --output .crds-gen.tmp && \
	ls "$$tmp_dir"/*.yaml >/dev/null 2>&1 && \
	rm -f $(CRD_SUBCHART_DIR)/templates/*.yaml && \
	mv "$$tmp_dir"/*.yaml $(CRD_SUBCHART_DIR)/templates/ && \
	rm -rf "$$tmp_dir";

	@bash $(CRD_SUBCHART_DIR)/scripts/labels.sh templates "everest.percona.com/crd=true,everest.percona.com/version=$(VERSION)";
