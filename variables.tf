variable "image_uri" {
  description = "ECR image URI for the Strapi container"
  type        = string
}

variable "codedeploy_role_arn" {
  description = "IAM role ARN for CodeDeploy to access ECS"
  type        = string
}
