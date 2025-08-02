variable "aws_region" {
  default = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID for networking"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "image_uri" {
  description = "Container image URI"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ARN of ECS task execution IAM role"
  type        = string
}

variable "codedeploy_role_arn" {
  description = "IAM role ARN for CodeDeploy"
  type        = string
}
