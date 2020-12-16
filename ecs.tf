resource "aws_ecs_cluster" "cluster" {
  name = var.name

  setting {
    name = "containerInsights"
    value = var.container_insights
  }

  tags = merge(local.all_tags, {
    "Name" = var.name
  })
}


data "template_file" "task_definition" {
  template = file("${path.module}/cxflow-task-definition.json")

  vars {
    environment = var.environment
    account_id = data.aws_caller_identity.current.account_id
    task_role_arn = aws_iam_role.ecs_task_execution_role.arn
    region = var.region
  }
}

resource "aws_ecs_task_definition" "cxflow" {
  family = "cxflow"
  container_definitions = data.template_file.task_definition.rendered

  tags = local.all_tags
}

resource "aws_ecs_service" "cxflow" {
  name = var.name
  cluster = "aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.cxflow.arn
  desired_count = var.desired_service_count
  iam_role = aws_iam_role.ecs_service.name

  network_configuration {
    subnets = module.vpc.public_subnets.*.ids
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.cxflow.id
    container_name = aws_ecr_repository.cxflow.name
    container_port = "8080"
  }

  tags = merge(local.all_tags, {
    "Name" = var.name
  })
}

resource "aws_lb" "cxflow" {
  name = var.name
  subnets = module.vpc.public_subnets.*.ids
  security_groups = [aws_security_group.alb.id]
  load_balancer_type = "application"

  tags = merge(local.all_tags, {
    "Name" = var.name
  })
}

resource "aws_lb_listener" "https_forward" {
  load_balancer_arn = aws_lb.cxflow.arn
  port = 443
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.cxflow.arn
  }
}

resource "aws_lb_target_group" "cxflow" {
  name = var.name
  port = 443
  protocol = "HTTP"
  vpc_id = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold = "3"
    interval = "90"
    protocol = "HTTP"
    matcher = "200-299"
    timeout = "20"
    path = "/"
    unhealthy_threshold = "2"
  }
}
