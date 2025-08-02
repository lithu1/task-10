output "alb_dns_name" {
  description = "Public ALB DNS Name"
  value       = aws_lb.this.dns_name
}

output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.strapi.name
}

output "codedeploy_app_name" {
  description = "CodeDeploy Application Name"
  value       = aws_codedeploy_app.ecs.name
}

output "codedeploy_group_name" {
  description = "CodeDeploy Deployment Group Name"
  value       = aws_codedeploy_deployment_group.ecs.deployment_group_name
}

output "service_name" {
  description = "ECS Service Name"
  value       = aws_ecs_service.strapi.name
}
