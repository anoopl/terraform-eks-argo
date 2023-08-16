output "configure_kubectl" {
  description = "Configure kubectl: makse sure you have aws-cli installed and configure to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

#ECR related outputs
output "repository_arn" {
  description = "Full ARN of the repository"
  value       = module.ecr.repository_arn
}

output "repository_registry_id" {
  description = "The registry ID where the repository was created"
  value       = module.ecr.repository_registry_id
}

output "repository_url" {
  description = "The URL of the repository (in the form `aws_account_id.dkr.ecr.region.amazonaws.com/repositoryName`)"
  value       = module.ecr.repository_url
}

