variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-2"
}

variable "ecs_cluster_name" {
  default = "strapi-cluster"
}

variable "ecs_task_cpu" {
  default = "512"
}

variable "ecs_task_memory" {
  default = "1024"
}

variable "strapi_container_port" {
  default = 1337
}

variable "strapi_image" {
  default = "607700977843.dkr.ecr.us-east-2.amazonaws.com/strapi-ecr-prod:latest"
}

variable "alb_name" {
  default = "strapi-alb"
}

variable "blue_target_group_name" {
  default = "strapi-blue"
}

variable "green_target_group_name" {
  default = "strapi-green"
}

variable "deployment_group_name" {
  default = "StrapiDeploymentGroup"
}

variable "codedeploy_app_name" {
  default = "StrapiApp"
}

variable "ecs_service_name" {
  default = "strapi-service"
}
