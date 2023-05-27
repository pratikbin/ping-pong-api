#!/usr/bin/make -f

COMMIT := $(shell git rev-parse --short HEAD)

## Docker variables
DOCKER_CONTAINER_NAME := ping-pong-api
DOCKER_REGISTRY := pratikbin
DOCKER_TAG_NAME := edge
DOCKER_IMAGE_NAME := $(DOCKER_REGISTRY)/$(DOCKER_CONTAINER_NAME)
DOCKER_IMAGE := $(DOCKER_IMAGE_NAME):$(DOCKER_TAG_NAME)

## Kubernets variables
KIND_IMAGE := "kindest/node:v1.24.13@sha256:cea86276e698af043af20143f4bf0509e730ec34ed3b7fa790cc0bea091bc5dd"
KUBECONFIG := ./kubeconfig.yaml
INGRESS_MANIFESTS := https://raw.githubusercontent.com/kubernetes/ingress-nginx/897783557a178dc09b6cd7ec25d9719c556ee3b9/deploy/static/provider/kind/deploy.yaml

## Run locally
all: check-node run

run:
	${MAKE} check-node
	@echo "Running locally"
	npm install
	node ./server.js

check-all:
	@echo "Checking all tools"
	@echo

	@echo "Node.js"
	${MAKE} check-node
	@echo

	@echo "Git"
	${MAKE} check-git
	@echo

	@echo "Docker"
	${MAKE} check-docker
	@echo

	@echo "Docker compose"
	${MAKE} check-docker-compose
	@echo

	@echo "Kubectl"
	${MAKE} check-kubectl
	@echo

	@echo "Kind"
	${MAKE} check-kind
	@echo

check-node:
	@node --version

check-docker:
	@docker version

check-docker-compose:
	@docker compose version

check-kubectl:
	@kubectl version

check-git:
	@git version

check-kind:
	@kind version

enable-docker-buildx:
	@echo "Ensuring docker buildx is setup"
	@docker buildx install
	@docker buildx use default

docker-build:
	@echo "Building images"
	docker build -t ${DOCKER_IMAGE} .

docker-build-no-cache:
	@echo "Building image without cache"
	docker build -t ${DOCKER_IMAGE} . --no-cache

docker-run-prep:
	docker compose up ${DOCKER_OPTS}

docker-run:
	@echo "Running Docker compose in background"
	${MAKE} docker-run-prep DOCKER_OPTS="-d"

docker-stop:
	@echo "Stopping Docker compose"
	docker compose stop

docker-run-it:
	@echo "Running Docker compose up in interactive"
	${MAKE} docker-run-prep

docker-push: docker-build
	@echo "Building image"
	docker push ${DOCKER_IMAGE}

docker-push-prod: docker-build
	@echo "Pushing prod image image"
	docker tag ${DOCKER_IMAGE} ${DOCKER_IMAGE_NAME}:latest-${COMMIT}
	docker tag ${DOCKER_IMAGE} ${DOCKER_IMAGE_NAME}:latest
	docker push ${DOCKER_IMAGE_NAME}:latest-${COMMIT}
	docker push ${DOCKER_IMAGE_NAME}:latest
	@echo
	@echo "=========== Pushed production images ${DOCKER_IMAGE_NAME} with tag latest-${COMMIT}, latest ============"
	@echo

docker-clean-container:
	@echo "Cleaning containers"
	-docker stop ${DOCKER_CONTAINER_NAME}
	-docker rm ${DOCKER_CONTAINER_NAME}

docker-clean-image:
	@echo "Cleaning image"
	-docker rmi ${DOCKER_IMAGE}

docker-compose-clean:
	@echo "Cleaning docker compose"
	-docker compose down -t0 -v

docker-clean: docker-compose-clean docker-clean-container docker-clean-image

create-k8s-cluster:
	@echo "Creating kubernets cluster using kind"
	KIND_IMAGE=${KIND_IMAGE} DOCKER_CONTAINER_NAME=${DOCKER_CONTAINER_NAME} ./kind.sh
	@echo "Wait few minutes to get cluster in ready state"
	@sleep 60
	kind get kubeconfig --name ${DOCKER_CONTAINER_NAME} >${KUBECONFIG}
	KUBECONFIG=${KUBECONFIG} kubectl apply -f ${INGRESS_MANIFESTS}
	@echo "Waiting for ingress to get up"
	KUBECONFIG=${KUBECONFIG} kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
	@echo "Ingress is up"
	@echo "Ready to deploy stuff"

delete-cluster:
	kind delete cluster --name ${DOCKER_CONTAINER_NAME}

k8s-apply: docker-build
	kind load docker-image ${DOCKER_IMAGE} --nodes ${DOCKER_CONTAINER_NAME}-control-plane --name ${DOCKER_CONTAINER_NAME}
	KUBECONFIG=${KUBECONFIG} kubectl apply -f ./k8s/

k8s-clean:
	-KUBECONFIG=${KUBECONFIG} kubectl delete -f ./k8s/
	-${MAKE} delete-cluster
	-rm ${KUBECONFIG}

clean: docker-clean k8s-clean
	@echo "Cleaning local node_modules"
	-rm -rf node_modules

.PHONY: all create-k8s-cluster delete-cluster k8s-apply k8s-clean install build verify docker-run docker-interactive check-all check-node check-docker check-docker-compose check-kubectl check-git enable-docker-buildx docker-build docker-build-no-cache docker-run-prep docker-push docker-push-prod docker-compose docker-compose-it docker-clean-container docker-clean-image docker-compose-clean docker-clean clean
