provider "aws" {
  region = "us-east-2"
}

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
  description = "Allow ALB to connect"
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
  subnets            = data.aws_subnets.default.ids
}

# Target Groups
resource "aws_lb_target_group" "blue" {
  name     = "blue-tg-${random_id.suffix.hex}"
  port     = 1337
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  target_type = "ip"
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "green" {
  name     = "green-tg-${random_id.suffix.hex}"
  port     = 1337
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  target_type = "ip"
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ALB Listener
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
  name = "strapi-cluster-${random_id.suffix.hex}"
}

# ECS Task Definition (placeholder)
resource "aws_ecs_task_definition" "strapi" {
  family                   = "strapi-task-${random_id.suffix.hex}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = "arn:aws:iam::607700977843:role/ecs-task-execution-role"
  container_definitions = jsonencode([
    {
      name      = "strapi"
      image     = "607700977843.dkr.ecr.us-east-2.amazonaws.com/strapi-ecr-prod:latest"
      essential = true
      portMappings = [
        {
          containerPort = 1337
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "this" {
  name            = "strapi-svc-${random_id.suffix.hex}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.strapi.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "strapi"
    container_port   = 1337
  }
  depends_on = [aws_lb_listener.http]
}

# CodeDeploy App
resource "aws_codedeploy_app" "ecs" {
  name              = "strapi-app-${random_id.suffix.hex}"
  compute_platform  = "ECS"
}

# CodeDeploy IAM Role
resource "aws_iam_role" "codedeploy_role" {
  name = "codedeploy-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codedeploy.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_attach" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForECS"
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "ecs_dg" {
  app_name              = aws_codedeploy_app.ecs.name
  deployment_group_name = "strapi-app-${random_id.suffix.hex}-cd-dg"
  service_role_arn      = aws_iam_role.codedeploy_role.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.this.name
    service_name = aws_ecs_service.this.name
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

  depends_on = [aws_lb_listener.http]
}
