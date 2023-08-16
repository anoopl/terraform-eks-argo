APP_NAME="app-test"
VERSION=$(shell cat ./version.txt)
ECR_REPO_URL=$(shell cat ./ecr_repo.txt)
KUBECONFIG_CMD=$(shell cat ./get_kubeconfig.txt)
DOCKER_LOGIN_CMD=$(shell cat ./get_dockerlogin.txt)
version: ## Show the version
	@echo $(VERSION)
build: ## Build the app image
	docker build -t $(APP_NAME) .
tag-version: ## Tage the image
	@echo 'create tag $(VERSION)'
	docker tag $(APP_NAME) $(ECR_REPO_URL):$(VERSION)
get-kubeconfig:
	@echo 'Get the Kubeconfig file for the EKS cluster'
	aws $(KUBECONFIG_CMD)
get-docker-login:
	@echo 'Get the docker credentials for the ECR repo'
	aws $(DOCKER_LOGIN_CMD)
push-version: tag-version ## Push the image `{version}`  to ECR
	@echo 'push $(VERSION) to $(ECR_REPO_URL)'
	docker push $(ECR_REPO_URL):$(VERSION)
deploy-app:
	@echo Deploy the app using ArgoCD
	kubectl apply -f argocd-github-token.yaml
	kubectl apply -f test-app-argocd.yaml


