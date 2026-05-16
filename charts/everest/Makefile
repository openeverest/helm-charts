HELM ?= helm

# values to override
IMAGE_PREFIX ?= ghcr.io/openeverest
EVEREST_SERVER_IMAGE_NAME ?= openeverest
EVEREST_OPERATOR_IMAGE_NAME ?= openeverest-operator
EVEREST_CATALOG_IMAGE_NAME ?= openeverest-catalog
TELEMETRY ?= true
VERSION ?= 1.14.0
CHART_VERSION ?= $(VERSION)
GH_PAGES_WORKTREE ?= /tmp/helm-gh-pages

.PHONY: prepare-chart
prepare-chart:
	CHART_FILES="Chart.yaml ./charts/everest-db-namespace/Chart.yaml ./charts/everest-crds/Chart.yaml"; \
	for chart in $$CHART_FILES; do \
		yq eval -i '.version = "${CHART_VERSION}"' $$chart; \
		yq eval -i '.appVersion = "${VERSION}"' $$chart; \
	done
	yq eval -i '.server.image = "$(IMAGE_PREFIX)/$(EVEREST_SERVER_IMAGE_NAME)"' values.yaml
	yq eval -i '.olm.catalogSourceImage = "$(IMAGE_PREFIX)/$(EVEREST_CATALOG_IMAGE_NAME)"' values.yaml
	yq eval -i '.operator.image = "$(IMAGE_PREFIX)/$(EVEREST_OPERATOR_IMAGE_NAME)"' values.yaml
	yq eval -i '.telemetry = $(TELEMETRY)' values.yaml
	yq eval -i '(.dependencies[] | select(.name == "everest-db-namespace")).version = "${CHART_VERSION}"' Chart.yaml
	yq eval -i '(.dependencies[] | select(.name == "everest-crds")).version = "${CHART_VERSION}"' Chart.yaml
	$(MAKE) deps
	

.PHONY: release-crds
release-crds:
	VERSION=$(VERSION) \
	$(MAKE) release -C charts/everest-crds


.PHONY: release
release: release-crds
release: prepare-chart

.PHONY: release-dev
release-dev: EVEREST_SERVER_IMAGE_NAME := openeverest-dev
release-dev: EVEREST_OPERATOR_IMAGE_NAME := openeverest-operator-dev
release-dev: EVEREST_CATALOG_IMAGE_NAME := openeverest-catalog-dev
release-dev: TELEMETRY=false
release-dev: release-crds
release-dev: prepare-chart

.PHONY: publish
publish:
	git worktree remove --force $(GH_PAGES_WORKTREE) 2>/dev/null || true
	git worktree add $(GH_PAGES_WORKTREE) gh-pages
	$(HELM) package . -d $(GH_PAGES_WORKTREE)
	$(HELM) package ./charts/everest-crds -d $(GH_PAGES_WORKTREE)
	$(HELM) package ./charts/everest-db-namespace -d $(GH_PAGES_WORKTREE)
	$(HELM) repo index $(GH_PAGES_WORKTREE) --merge $(GH_PAGES_WORKTREE)/index.yaml
	cd $(GH_PAGES_WORKTREE) && git add -A && git commit -m "Release chart v$(CHART_VERSION) (app v$(VERSION))" && git push origin gh-pages
	git worktree remove --force $(GH_PAGES_WORKTREE)

.PHONY: release-and-publish
release-and-publish: release publish

.PHONY: add-repos
add-repos:
	$(HELM) version
	$(HELM) repo add prometheus-community https://prometheus-community.github.io/helm-charts
	$(HELM) repo add vm https://victoriametrics.github.io/helm-charts
	$(HELM) repo add percona https://percona.github.io/percona-helm-charts/
	$(HELM) repo add percona-olm https://percona.github.io/operator-lifecycle-manager

.PHONY: deps
deps: add-repos
	$(HELM) dependency update .
	$(HELM) dependency update ./charts/everest-db-namespace
	$(HELM) dependency update ./charts/pmm3

# Like 'deps' but uses the lock file without updating repo indices — fast when .tgz files are cached.
.PHONY: deps-build
deps-build: add-repos
	$(HELM) dependency build .
	$(HELM) dependency build ./charts/everest-db-namespace
	$(HELM) dependency build ./charts/pmm3

.PHONY: docs-gen
docs-gen:
	docker run --rm -v "$(PWD)/:/helm-docs" -u $(shell id -u) jnorwood/helm-docs:v1.14.2

.PHONY: test
test:
	$(HELM) template test . --namespace everest-system
	$(HELM) template test . --namespace everest-system -f test/test-values.yaml

.PHONY: link-crds
link-crds:
	@mkdir -p crds
	@for crd in charts/everest-crds/templates/*.yaml; do \
		ln -sf "../$${crd}" crds/; \
		echo "Linked $$crd → crds/"; \
	done

EVEREST_OPERATOR_REPO_URL ?= https://github.com/openeverest/openeverest-operator
OPENEVEREST_REPO_URL ?= https://github.com/openeverest/openeverest
CRD_DIR ?= config/crd
CRD_VERSION ?= main
# FIXME: this is temporary until we have a split between v1 and v2
OPENEVEREST_CRD_VERSION ?= v2
.PHONY: crds-gen
crds-gen:
	EVEREST_OPERATOR_REPO_URL=$(EVEREST_OPERATOR_REPO_URL) \
	OPENEVEREST_REPO_URL=$(OPENEVEREST_REPO_URL) \
	CRD_DIR=$(CRD_DIR) \
	CRD_VERSION=$(CRD_VERSION) \
	OPENEVEREST_CRD_VERSION=$(OPENEVEREST_CRD_VERSION) \
	VERSION=$(VERSION) \
	CRD_SUBCHART_DIR=$(PWD)/charts/everest-crds \
	$(MAKE) -C charts/everest-crds crds-gen

.PHONY: controller-manifests-gen
controller-manifests-gen: ## Sync controller RBAC manifests from the openeverest repo into Helm templates.
	OPENEVEREST_REPO_URL=$(OPENEVEREST_REPO_URL) \
	OPENEVEREST_VERSION=$(OPENEVEREST_CRD_VERSION) \
	OUTPUT_DIR=$(PWD)/templates/everest-controller \
	bash $(PWD)/scripts/sync-controller-rbac.sh

.PHONY: controller-webhook-gen
controller-webhook-gen: ## Sync controller webhook manifests from the openeverest repo into Helm templates.
	OPENEVEREST_REPO_URL=$(OPENEVEREST_REPO_URL) \
	OPENEVEREST_VERSION=$(OPENEVEREST_CRD_VERSION) \
	OUTPUT_DIR=$(PWD)/templates/everest-controller \
	bash $(PWD)/scripts/sync-controller-webhook.sh

.PHONY: controller-deployment-gen
controller-deployment-gen: ## Sync controller deployment from the openeverest repo into Helm templates.
	OPENEVEREST_REPO_URL=$(OPENEVEREST_REPO_URL) \
	OPENEVEREST_VERSION=$(OPENEVEREST_CRD_VERSION) \
	OUTPUT_DIR=$(PWD)/templates/everest-controller \
	bash $(PWD)/scripts/sync-controller-deployment.sh

.PHONY: prepare-pr
prepare-pr:
	$(MAKE) deps
	$(MAKE) docs-gen
	EVEREST_OPERATOR_REPO_URL=$(EVEREST_OPERATOR_REPO_URL) \
	CRD_DIR=$(CRD_DIR) \
	CRD_VERSION=$(CRD_VERSION) $(MAKE) crds-gen link-crds
	$(MAKE) controller-manifests-gen
	$(MAKE) controller-webhook-gen
	$(MAKE) controller-deployment-gen
