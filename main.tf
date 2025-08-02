provider "aws" {
  region = "us-east-2"
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  app_name = "strapi-app-${random_id.suffix.hex}"
}

# Get default VPC and Subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_subnet" "selected" {
  count = 2 # Choose how many AZs/subnets you want ALB in (2 or 3 is fine)
  id    = tolist(data.aws_subnet_ids.all.ids)[count.index]
}

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg-${random_id.suffix.hex}"
  description = "Allow HTTP/HTTPS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Security Group
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-sg-${random_id.suffix.hex}"
  description = "Allow traffic from ALB on port 1337"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 1337
    to_port         = 1337
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB
resource "aws_lb" "this" {
  name               = "alb-${random_id.suffix.hex}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in data.aws_subnet.selected : s.id]
}

# Target Groups
resource "aws_lb_target_group" "blue" {
  name        = "tg-blue-${random_id.suffix.hex}"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "green" {
  name        = "tg-green-${random_id.suffix.hex}"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = "${local.app_name}-cluster"
}

# Task Definition
resource "aws_ecs_task_definition" "strapi" {
  family                   = "${local.app_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = "arn:aws:iam::607700977843:role/ecs-task-execution-role"
  task_role_arn            = "arn:aws:iam::607700977843:role/ecs-task-execution-role"

  container_definitions = jsonencode([
    {
      name  = "strapi"
      image = "607700977843.dkr.ecr.us-east-2.amazonaws.com/strapi-ecr-prod:latest"
      portMappings = [
        {
          containerPort = 1337
          hostPort      = 1337
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service with CODE_DEPLOY
resource "aws_ecs_service" "strapi" {
  name            = "${local.app_name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.strapi.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = [for s in data.aws_subnet.selected : s.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "strapi"
    container_port   = 1337
  }

  depends_on = [aws_lb_listener.http]
}

# CodeDeploy Application
resource "aws_codedeploy_app" "ecs_app" {
  name             = "${local.app_name}-cd-app"
  compute_platform = "ECS"
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "ecs_dg" {
  app_name              = aws_codedeploy_app.ecs_app.name
  deployment_group_name = "${local.app_name}-cd-dg"
  service_role_arn      = "arn:aws:iam::607700977843:role/ecs-task-execution-role"

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout    = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }

    green_fleet_provisioning_option {
      action = "DISCOVER_EXISTING"
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.this.name
    service_name = aws_ecs_service.strapi.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      target_group {
        name = aws_lb_target_group.blue.name
      }

      target_group {
        name = aws_lb_target_group.green.name
      }
    }
  }

  depends_on = [aws_ecs_service.strapi]
}

output "alb_dns" {
  value = aws_lb.this.dns_name
}
