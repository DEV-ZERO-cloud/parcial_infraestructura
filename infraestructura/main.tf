data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_caller_identity" "current" {}

locals {
  create_iam_roles = var.existing_iam_role_arn == ""
  create_oidc      = var.github_repo != "" && local.create_iam_roles
}

# ---------------------------------------------------------------------------
# Registro de imágenes (único): la imagen se construye una sola vez y ambos
# ambientes la consumen por digest. Tags inmutables y escaneo al subir.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # Permite terraform destroy aunque contenga imágenes publicadas

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    ambiente = "compartido"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conservar solo las ultimas 20 imagenes (control de costo)"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# Recursos parametrizados por ambiente (pruebas / produccion) con for_each
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  for_each = var.environments

  name              = "/ecs/estrella-${each.key}"
  retention_in_days = 30

  tags = {
    ambiente = each.key
  }
}

resource "aws_ecs_cluster" "env" {
  for_each = var.environments

  name = "estrella-${each.key}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    ambiente = each.key
  }
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Rol de ejecución: solo descargar imagen de ECR y enviar logs a CloudWatch.
resource "aws_iam_role" "execution" {
  for_each = local.create_iam_roles ? var.environments : {}

  name               = "estrella-${each.key}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = {
    ambiente = each.key
  }
}

resource "aws_iam_role_policy_attachment" "execution" {
  for_each = local.create_iam_roles ? var.environments : {}

  role       = aws_iam_role.execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Rol de la tarea: sin permisos adicionales (la app es stateless y no consume APIs de AWS).
resource "aws_iam_role" "task" {
  for_each = local.create_iam_roles ? var.environments : {}

  name               = "estrella-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = {
    ambiente = each.key
  }
}

resource "aws_security_group" "alb" {
  for_each = var.environments

  name        = "estrella-${each.key}-alb"
  description = "Entrada HTTP publica al balanceador"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    ambiente = each.key
  }
}

resource "aws_security_group" "task" {
  for_each = var.environments

  name        = "estrella-${each.key}-task"
  description = "Trafico permitido unicamente desde el balanceador hacia la tarea ECS"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    ambiente = each.key
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = var.environments

  security_group_id = aws_security_group.alb[each.key].id
  description       = "HTTP entrante desde internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    ambiente = each.key
  }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_task" {
  for_each = var.environments

  security_group_id            = aws_security_group.alb[each.key].id
  description                  = "Salida desde el balanceador hacia las tareas ECS"
  ip_protocol                  = "tcp"
  from_port                    = var.target_port
  to_port                      = var.target_port
  referenced_security_group_id = aws_security_group.task[each.key].id

  tags = {
    ambiente = each.key
  }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  for_each = var.environments

  security_group_id            = aws_security_group.task[each.key].id
  description                  = "Entrada a la tarea unicamente desde el balanceador"
  ip_protocol                  = "tcp"
  from_port                    = var.target_port
  to_port                      = var.target_port
  referenced_security_group_id = aws_security_group.alb[each.key].id

  tags = {
    ambiente = each.key
  }
}

# La tarea necesita salida HTTPS (443) para descargar la imagen desde ECR y escribir logs en CloudWatch.
resource "aws_vpc_security_group_egress_rule" "task_https" {
  for_each = var.environments

  security_group_id = aws_security_group.task[each.key].id
  description       = "HTTPS saliente hacia ECR y CloudWatch Logs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    ambiente = each.key
  }
}

resource "aws_lb" "app" {
  for_each = var.environments

  name                       = "estrella-${each.key}"
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = data.aws_subnets.default.ids
  security_groups            = [aws_security_group.alb[each.key].id]
  drop_invalid_header_fields = true
  enable_deletion_protection = false # Permite ejecutar terraform destroy al finalizar

  tags = {
    ambiente = each.key
  }
}

resource "aws_lb_target_group" "app" {
  for_each = var.environments

  name        = "estrella-${each.key}"
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    ambiente = each.key
  }
}

resource "aws_lb_listener" "http" {
  for_each = var.environments

  load_balancer_arn = aws_lb.app[each.key].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  tags = {
    ambiente = each.key
  }
}

resource "aws_ecs_task_definition" "app" {
  for_each = var.environments

  family                   = "estrella-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = local.create_iam_roles ? aws_iam_role.execution[each.key].arn : var.existing_iam_role_arn
  task_role_arn            = local.create_iam_roles ? aws_iam_role.task[each.key].arn : var.existing_iam_role_arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.placeholder_image
    essential = true
    portMappings = [{
      containerPort = var.target_port
      hostPort      = var.target_port
      protocol      = "tcp"
    }]
    environment = [
      { name = "APP_ENV", value = each.key },
      { name = "PORT", value = tostring(var.target_port) }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app[each.key].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
  }])

  tags = {
    ambiente = each.key
  }

  # CI/CD registra nuevas revisiones con la imagen por digest (@sha256:...).
  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "app" {
  for_each = var.environments

  name                              = "app"
  cluster                           = aws_ecs_cluster.env[each.key].id
  task_definition                   = aws_ecs_task_definition.app[each.key].arn
  desired_count                     = each.value.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.task[each.key].id]
    assign_public_ip = true # Evita el costo fijo de un NAT Gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app[each.key].arn
    container_name   = "app"
    container_port   = var.target_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = {
    ambiente = each.key
  }

  depends_on = [aws_lb_listener.http]

  # La promoción de la imagen la realiza GitHub Actions; Terraform no debe revertirla.
  lifecycle {
    ignore_changes = [task_definition]
  }
}

# ---------------------------------------------------------------------------
# OIDC para GitHub Actions (sin llaves estáticas guardadas en el repositorio)
# Solo se crea si se define var.github_repo y la cuenta permite crear IAM.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = local.create_oidc && var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    ambiente = "compartido"
  }
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? try(aws_iam_openid_connect_provider.github[0].arn, "") : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_assume" {
  count = local.create_oidc ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github" {
  count = local.create_oidc ? 1 : 0

  name               = "estrella-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json

  tags = {
    ambiente = "compartido"
  }
}

data "aws_iam_policy_document" "github_permissions" {
  count = local.create_oidc ? 1 : 0

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid = "EcsTaskDefinitions"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "EcsUpdateServices"
    actions = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = [
      for k, s in aws_ecs_service.app :
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.env[k].name}/${s.name}"
    ]
  }

  statement {
    sid     = "PassTaskRoles"
    actions = ["iam:PassRole"]
    resources = concat(
      [for r in aws_iam_role.execution : r.arn],
      [for r in aws_iam_role.task : r.arn],
    )
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github" {
  count = local.create_oidc ? 1 : 0

  name   = "estrella-github-actions"
  role   = aws_iam_role.github[0].id
  policy = data.aws_iam_policy_document.github_permissions[0].json
}