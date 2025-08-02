variable "region" {
  default = "us-east-2"
}

variable "app_name" {
  default = "strapi-app"
}

variable "container_port" {
  default = 1337
}
variable "image_url" {
  description = "Docker image URL for the ECS task definition"
  type        = string
}
variable "image_url" {
  description = "Docker image URL for the ECS task definition"
  type        = string
}
