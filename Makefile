IMG ?= github.com/yardbirdsax/home-automation/api
IMG_TAG ?= latest


# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development
.PHONY: helm
helm: kustomize helmify ## Generate Helm charts
	$(KUSTOMIZE) build config/default | $(HELMIFY) charts/k8s-controller

.PHONY: generate
generate: setup
	go generate ./...

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: test-fmt
test-fmt:
	test -z "$$(make fmt)"

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: generate test-fmt vet ## Run tests.
	go test ./... -coverprofile=coverage.out

.PHONY: test-e2e
test-e2e: start docker-build docker-load deploy
	go test -v -tags=e2e -count=1 ./test --timeout 30s; \
	if [ $$? -eq 0 ]; then \
		echo "test succeeded"; \
	else \
		echo "test failed!"; \
	fi;
	make stop

##@ Build

.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	docker build -t ${IMG}:${IMG_TAG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG_REGISTRY}/${IMG}:${IMG_TAG}

.PHONY: docker-tag
docker-tag: ## Tag docker image with a new registry URL attached
	docker tag ${IMG}:${IMG_TAG} ${IMG_REGISTRY}/${IMG}:${IMG_TAG}

.PHONY: docker-load
docker-load: ## Loads the image onto the local k3d cluster
	$(K3D) image load ${IMG}:${IMG_TAG} -c $(K3D_CLUSTER_NAME)


##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	make helm
	helm install $(HELM_RELEASE_NAME) charts/k8s-controller

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	helm uninstall $(HELM_RELEASE_NAME)

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

PATHPLUSLOCALBIN = PATH=$(LOCALBIN):$$PATH

## Tool Binaries
K3D ?= k3d
CTLPTL ?= go tool ctlptl
HELMIFY ?= go tool helmify
KUSTOMIZE ?= go tool kustomize

# Local environment setup
.PHONY: setup
setup:
	asdf install
.PHONY: start
start:
	$(CTLPTL) apply -f cluster.yaml
stop:
	$(CTLPTL) delete -f cluster.yaml

