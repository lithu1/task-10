# main.tf

provider "aws" {
  region = var.region
}

# Use pre-existing ECS task execution role
data "aws_iam_role" "ecs_task_execution" {
  name = "ecs-task-execution-role"
}

resource "aws_ecs_cluster" "strapi" {
  name = "${var.app_name}-cluster"
}

# Use pre-existing security group
data "aws_security_group" "lb" {
  filter {
    name   = "group-name"
    values = ["strapi-alb-sg"]
  }
  vpc_id = data.aws_vpc.default.id
}

# ALB
resource "aws_lb" "this" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.aws_security_group.lb.id]
  subnets            = data.aws_subnets.default.ids
}

# Use pre-existing Target Group
data "aws_lb_target_group" "strapi" {
  name = "strapi-tg"
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = data.aws_lb_target_group.strapi.arn
  }
}

resource "aws_ecs_task_definition" "strapi" {
  family                   = "${var.app_name}-task"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn
  container_definitions = jsonencode([
    {
      name      = "${var.app_name}"
      image     = var.image_url
      portMappings = [
        {
          containerPort = var.container_port
          protocol       = "tcp"
        }
      ]
      essential = true
    }
  ])
}

resource "aws_ecs_service" "strapi" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.strapi.id
  task_definition = aws_ecs_task_definition.strapi.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [data.aws_security_group.lb.id]
    assign_public_ip = true
  }

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  load_balancer {
    target_group_arn = data.aws_lb_target_group.strapi.arn
    container_name   = var.app_name
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
}

# Use existing CodeDeploy application
data "aws_codedeploy_app" "ecs" {
  name = "strapi-codedeploy-app"
}

resource "aws_codedeploy_deployment_group" "ecs" {
  app_name               = data.aws_codedeploy_app.ecs.name
  deployment_group_name = "${var.app_name}-deploy-group"
  service_role_arn       = data.aws_iam_role.ecs_task_execution.arn

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.strapi.name
    service_name = aws_ecs_service.strapi.name
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
}

# Data Sources for default VPC and Subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
