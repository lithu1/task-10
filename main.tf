# Generate random suffix
resource "random_id" "suffix" {
  byte_length = 4
}

# Get default VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Extract two subnets from different AZs to avoid ALB subnet conflict
locals {
  alb_subnets = slice(data.aws_subnets.default.ids, 0, 2)
}

# ECS Cluster
resource "aws_ecs_cluster" "strapi" {
  name = "${var.app_name}-${random_id.suffix.hex}-cluster"
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "${var.app_name}-${random_id.suffix.hex}-alb-sg"
  description = "Allow HTTP/HTTPS to ALB"
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

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_sg" {
  name        = "${var.app_name}-${random_id.suffix.hex}-ecs-sg"
  description = "Allow ALB to ECS on container port"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
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

# Application Load Balancer
resource "aws_lb" "this" {
  name               = "${var.app_name}-${random_id.suffix.hex}-alb"
  load_balancer_type = "application"
  subnets            = local.alb_subnets
  security_groups    = [aws_security_group.alb_sg.id]
}

# Target Groups
resource "aws_lb_target_group" "blue" {
  name        = "${var.app_name}-${random_id.suffix.hex}-blue-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "green" {
  name        = "${var.app_name}-${random_id.suffix.hex}-green-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 10
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

# IAM Roles
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.app_name}-${random_id.suffix.hex}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_role_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Definition
resource "aws_ecs_task_definition" "strapi_task" {
  family                   = "${var.app_name}-${random_id.suffix.hex}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "strapi"
      image     = var.image_url
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "strapi" {
  name            = "${var.app_name}-${random_id.suffix.hex}-svc"
  cluster         = aws_ecs_cluster.strapi.id
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.strapi_task.arn
  desired_count   = 1
  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "strapi"
    container_port   = var.container_port
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_ecs_task_definition.strapi_task]
}

# IAM Role for CodeDeploy
resource "aws_iam_role" "codedeploy_role" {
  name = "${var.app_name}-${random_id.suffix.hex}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codedeploy.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_attach" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# CodeDeploy App and Deployment Group
resource "aws_codedeploy_app" "ecs" {
  name             = "${var.app_name}-${random_id.suffix.hex}-cd-app"
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "ecs" {
  app_name               = aws_codedeploy_app.ecs.name
  deployment_group_name  = "${var.app_name}-${random_id.suffix.hex}-deploy-group"
  service_role_arn       = aws_iam_role.codedeploy_role.arn
  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  ecs_service {
    cluster_name = aws_ecs_cluster.strapi.name
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

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                            = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
}
