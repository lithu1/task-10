// main.tf

// ----------------------
// DATA SOURCES
// ----------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

// ----------------------
// ECS CLUSTER
// ----------------------
resource "aws_ecs_cluster" "strapi" {
  name = var.ecs_cluster_name
}

// ----------------------
// IAM ROLES
// ----------------------
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

// ----------------------
// SECURITY GROUPS
// ----------------------
resource "aws_security_group" "alb_sg" {
  name   = "strapi-alb-sg"
  vpc_id = data.aws_vpc.default.id

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

resource "aws_security_group" "ecs_sg" {
  name   = "strapi-ecs-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = var.strapi_container_port
    to_port         = var.strapi_container_port
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

// ----------------------
// APPLICATION LOAD BALANCER
// ----------------------
resource "aws_lb" "strapi_alb" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.public.ids
}

resource "aws_lb_target_group" "blue" {
  name        = var.blue_target_group_name
  port        = var.strapi_container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"
  health_check {
    path = "/"
    port = tostring(var.strapi_container_port)
  }
}

resource "aws_lb_target_group" "green" {
  name        = var.green_target_group_name
  port        = var.strapi_container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"
  health_check {
    path = "/"
    port = tostring(var.strapi_container_port)
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.strapi_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

// ----------------------
// ECS TASK DEFINITION
// ----------------------
resource "aws_ecs_task_definition" "strapi" {
  family                   = "strapi-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  container_definitions = jsonencode([{
    name      = "strapi"
    image     = var.strapi_image
    portMappings = [{ containerPort = var.strapi_container_port, protocol = "tcp" }]
  }])
}

// ----------------------
// ECS SERVICE WITH CODEDEPLOY
// ----------------------
resource "aws_ecs_service" "strapi" {
  name            = var.ecs_service_name
  cluster         = aws_ecs_cluster.strapi.id
  task_definition = aws_ecs_task_definition.strapi.arn
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets         = data.aws_subnets.public.ids
    assign_public_ip = true
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "strapi"
    container_port   = var.strapi_container_port
  }
}

// ----------------------
// CODEDEPLOY CONFIGURATION
// ----------------------
resource "aws_codedeploy_app" "strapi" {
  name             = var.codedeploy_app_name
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "strapi" {
  app_name              = aws_codedeploy_app.strapi.name
  deployment_group_name = var.deployment_group_name
  service_role_arn      = aws_iam_role.codedeploy_service.arn

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    green_fleet_provisioning_option {
      action = "DISCOVER_EXISTING"
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

  load_balancer_info {
    target_group_pair_info {
      target_group {
        name = aws_lb_target_group.blue.name
      }

      target_group {
        name = aws_lb_target_group.green.name
      }

      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }
    }
  }
}
