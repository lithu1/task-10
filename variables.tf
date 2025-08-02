variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "image_url" {
  description = "Full Docker image URL for ECS task"
  type        = string
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 1337
}

variable "app_name" {
  description = "Name prefix for all AWS resources"
  type        = string
  default     = "strapi-app"
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 1
}
