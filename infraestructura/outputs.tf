output "aws_region" {
  description = "Región de AWS (variable AWS_REGION en GitHub Actions)."
  value       = var.aws_region
}

output "ecr_repository_name" {
  description = "Nombre del repositorio ECR."
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  description = "URI del repositorio ECR; la imagen se publica como <url>:<sha> y se promueve como <url>@sha256:<digest>."
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_clusters" {
  description = "Nombre del cluster ECS por ambiente."
  value       = { for k, v in aws_ecs_cluster.env : k => v.name }
}

output "ecs_services" {
  description = "Nombre del servicio ECS por ambiente."
  value       = { for k, v in aws_ecs_service.app : k => v.name }
}

output "task_definition_families" {
  description = "Familia de la definición de tarea ECS por ambiente (para registrar nuevas revisiones con el digest)."
  value       = { for k, v in aws_ecs_task_definition.app : k => v.family }
}

output "app_urls" {
  description = "URL pública base (HTTP) del balanceador por ambiente."
  value       = { for k, v in aws_lb.app : k => "http://${v.dns_name}" }
}

output "health_urls" {
  description = "URL pública del endpoint /health por ambiente (para la variable HEALTH_URL en GitHub Environments)."
  value       = { for k, v in aws_lb.app : k => "http://${v.dns_name}/health" }
}

output "github_actions_role_arn" {
  description = "ARN del rol IAM OIDC para GitHub Actions (AWS_ROLE_ARN). Vacío si no se definió github_repo o si se usa LabRole."
  value       = try(aws_iam_role.github[0].arn, "")
}