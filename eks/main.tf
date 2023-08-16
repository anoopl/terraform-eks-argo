provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "bcrypt" {}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {}

locals {
  name   = basename(path.cwd)
  region = "us-east-1"

  cluster_version = "1.26"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Clusrername = local.name
  }
}

#Create VPC and Subnets

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0.2"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

#Create EKS CLuster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.13.1"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  #Setup EKS Add-ons
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 3
      max_size     = 10
      desired_size = 5
    }
  }

  tags = local.tags
}

#Configure EKS CLuster Add-ons using EKS Blueprint Kuberenetes-addons module

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.31.0/modules/kubernetes-addons"

  eks_cluster_id       = module.eks.cluster_name
  eks_cluster_endpoint = module.eks.cluster_endpoint
  eks_oidc_provider    = module.eks.oidc_provider
  eks_cluster_version  = module.eks.cluster_version

  enable_argocd = true
  argocd_helm_config = {
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argo.id
      }
    ]
  }


  argocd_manage_add_ons = true #Use ArgoCD to manage addons like CSI driver etc
  argocd_applications = {
    addons = {
      path               = "chart"
      repo_url           = "https://github.com/aws-samples/eks-blueprints-add-ons.git"
      add_on_application = true
    }
    #workloads = {
    #  path               = "envs/dev"
    #  repo_url           = "https://github.com/aws-samples/eks-blueprints-workloads.git"
    #  add_on_application = false
    #}
  }

  # Cluster Addons, ALB controller is used for the Ingress to expose the Test App
  enable_aws_load_balancer_controller = true
  enable_cert_manager                 = false
  #For autoscaling
  enable_keda                           = false
  enable_amazon_eks_aws_ebs_csi_driver  = false
  enable_aws_for_fluentbit              = false
  aws_for_fluentbit_create_cw_log_group = false
  #enable_cert_manager                   = false
  enable_cluster_autoscaler = false
  enable_karpenter          = false
  #enable_keda                           = false
  enable_metrics_server = true
  enable_prometheus     = true
  enable_traefik        = false
  enable_vpa            = false
  enable_yunikorn       = false
  enable_argo_rollouts  = true

  tags = local.tags
}

#Generate ArgoCD password and keep it in AWS KMS
resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#ArgoCD password generation using custom provider bcrypt
resource "bcrypt_hash" "argo" {
  cleartext = random_password.argocd.result
}

resource "aws_secretsmanager_secret" "argocd" {
  name                    = "argocd-1"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}

#Create ECR repo using a custom ECR module, so that it can be reused for creating more repos in future
module "ecr" {
  source = "terraform-aws-modules/ecr/aws"

  repository_name = "app-test"

  #repository_read_write_access_arns = ["arn:aws:iam::012345678901:role/terraform"]
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 30 images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = {
    App         = "test"
    Environment = "test"
  }
}

#Create an SSL Certificate to use with the ALB for the Test App
resource "aws_route53_zone" "this" {
  name = var.domain_name
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name = var.domain_name
  zone_id     = aws_route53_zone.this.zone_id

  subject_alternative_names = [
    "*.${var.domain_name}",
  ]

  validation_method = "EMAIL"

  tags = {
    Name = var.domain_name
  }
}

#Write Kubectl config to a file for using in other stages
resource "local_file" "kube_config_text" {
content  = "eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
filename = "../app-test/get_kubeconfig.txt"
}

#Write the command for ECR login using docker cli
resource "local_file" "docker_login" {
content = "ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${module.ecr.repository_registry_id}.dkr.ecr.${local.region}.amazonaws.com" 
filename = "../app-test/get_dockerlogin.txt"
}

#write the ECR repo url to a file which can be used for pushing docker image
resource "local_file" "ecr_repo_text" {
    content  = "${module.ecr.repository_url}"
    filename = "../app-test/ecr_repo.txt"
}

#write the SSL file to Helm values yaml for the test app
resource "local_file" "template" {
  content = templatefile("../app-test/values-test.yaml",{
    ssl_cert = "${module.acm.acm_certificate_arn}"
    ecr_repo  = "${module.ecr.repository_url}"
    })
  filename = "../values-test.yaml"
}
