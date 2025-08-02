output "alb_dns_name" {
  value = aws_lb.strapi_alb.dns_name
  description = "Public DNS name of the Application Load Balancer"
}

output "ecs_service_name" {
  value = aws_ecs_service.strapi.name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.strapi.name
}
