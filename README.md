# Terraform code for bootstrapping EKS with ArgoCD
Terraform code for bootstrapping EKS with ArgoCD

### Overview
1. A test app is created using Python Fast API which display a version number 
2. Terraform is used to create an EKS cluster and required resources
3. ArgoCD is bootstrapped with Terraform and it will be used to deploy the test app


## Directory structure

```
eks -> Terraform code for creating the EKS cluster and resources
app-test -> code, and deployment files for the test app
```

## Pre requisites
make sure you have installed following CLI tools

1. AWS CLI (https://aws.amazon.com/cli/)
2. kubectl CLI (https://kubernetes.io/docs/tasks/tools/ )
3. Docker CLI (https://github.com/docker/cli)

## Create the Kubernetes cluster on Amazon EKS with related resources like VPC, NAT Gateway, Elastic Container repo so on
```
cd eks

terraform init

terraform apply -var-file=test.tfvars
```

Please note that there is an Amazon Certificate Manager SSL certificate will be created by the Terraform, which requires and email authentciation to the test domain anoopl.in

You can change the test domain if needed by editing the file test.tfvars

Then the approval mail will be send to the default domain admin emails described as in this page below:
https://docs.aws.amazon.com/acm/latest/userguide/email-validation.html

## Build and Deploy the test app:

Once the EKS cluster is ready it will automatically bootstrap the ArgoCD.
We have a make file created to build and  deploy the app using ArgoCD
Since this is a private repo you need create Github token to access this repo then add the token to the argocd-github-token.yaml
before running the deploy command

Now you can deploy the app using the following commands:

```
cd app-test
make build
make tag-version
make get-kubeconfig
make get-docker-login
make push-version
make deploy-app
```


## To view the app in Argocd
```
kubectl -n argocd port-forward svc/argo-cd-argocd-server 9000:443
```
Now on your local machine you can access Argocd Admin url using:

http://localhost:9000

User Name: admin
To get the Argocd admin password from AWS KMS:

```
aws secretsmanager get-secret-value --secret-id argocd-1 --region us-east-1
```

Replace the region with the AWS region if you have changed it in the code

## Access the APP:

You can get app using the Load Balancer URL
You can get the load balancer url using the command:

```
kubectl -n test-app get ing
```

Then the Address field will have the ALB URL
example:
```
xxxx.us-east-1.elb.amazonaws.com 
https://alb-url
```

It should display the version number 0.1.0

## Destroy:

```cd eks
terraform destroy -target=module.eks_blueprints_kubernetes_addons -auto-approve
terraform destroy -target=module.eks -var-file=test.tfvars -auto-approve
terraform destroy -var-file=test.tfvars -auto-approve
```


### ToDO
1. Docker file with Google Distroless image
