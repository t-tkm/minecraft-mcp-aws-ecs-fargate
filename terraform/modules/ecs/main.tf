# =============================================================================
# ECS Module
# =============================================================================

resource "aws_cloudwatch_log_group" "minecraft_logs" {
  name              = "/ecs/${var.task_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = var.environment
  }
}

resource "aws_ecs_cluster" "minecraft" {
  name = "${var.project_name}-cluster"

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
  })
}

resource "aws_iam_role" "task_role" {
  name        = "${var.project_name}-task-role"
  description = "Allows ECS tasks to call AWS services on your behalf."

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ecs-tasks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  inline_policy {
    name = "CloudWatchLogsPolicy"
    policy = jsonencode({
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogStreams"
          ],
          "Resource" : "arn:aws:logs:${var.aws_region}:*:log-group:/ecs/${var.task_name}*"
        }
      ]
    })
  }

  inline_policy {
    name = "ECSExecPolicy"
    policy = jsonencode({
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
          ],
          "Resource" : "*"
        }
      ]
    })
  }

  tags = {
    Name        = "${var.project_name}-task-role"
    Environment = var.environment
  }
}

resource "aws_iam_role" "task_execution_role" {
  name = "${var.project_name}-task-execution-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ecs-tasks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  inline_policy {
    name = "ECRAccessPolicy"
    policy = jsonencode({
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage"
          ],
          "Resource" : "*"
        }
      ]
    })
  }

  tags = {
    Name        = "${var.project_name}-task-execution-role"
    Environment = var.environment
  }
}

resource "aws_ecs_task_definition" "minecraft" {
  cpu                = var.cpu
  execution_role_arn = aws_iam_role.task_execution_role.arn
  family             = var.task_name
  memory             = var.memory
  network_mode       = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn      = aws_iam_role.task_role.arn

  volume {
    name = "data"
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      root_directory     = "/"
      transit_encryption = "DISABLED"

      authorization_config {
        iam = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      command    = []
      cpu        = 0
      entryPoint = []
      environment = [
        {
          name  = "EULA"
          value = "TRUE"
        },
        {
          name  = "TYPE"
          value = "PAPER"
        },
        {
          name  = "JAVA_OPTS"
          value = "-Xms${var.java_memory_heap} -Xmx${var.java_memory_heap}"
        },
        {
          name  = "ONLINE_MODE"
          value = "false"
        },
        {
          name  = "GAMEMODE"
          value = "survival"
        },
        {
          name  = "DIFFICULTY"
          value = "normal"
        },
        {
          name  = "MAX_PLAYERS"
          value = "20"
        },
        {
          name  = "MOTD"
          value = "Minecraft on AWS ECS"
        },
        {
          name  = "ENABLE_RCON"
          value = "true"
        },
        {
          name  = "RCON_PASSWORD"
          value = var.rcon_password != null ? nonsensitive(var.rcon_password) : "default-password-123"
        },
        {
          name  = "VERSION"
          value = var.minecraft_version
        },
      ]
      essential = true
      image     = var.docker_image
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.task_name}"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
      memory            = var.container_memory
      memoryReservation = var.container_memory_reservation
      mountPoints = [
        {
          containerPath = "/data"
          sourceVolume  = "data"
        },
      ]
      name = var.container_name
      portMappings = [
        {
          containerPort = 25565
          hostPort      = 25565
          protocol      = "tcp"
        },
        {
          containerPort = 25575
          hostPort      = 25575
          protocol      = "tcp"
        },
      ]
    },
  ])

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-task"
    Environment = var.environment
  })
}

resource "aws_ecs_service" "minecraft" {
  name                               = "${var.project_name}-service"
  cluster                            = aws_ecs_cluster.minecraft.arn
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 0
  desired_count                      = 1
  enable_ecs_managed_tags            = true
  enable_execute_command             = true
  health_check_grace_period_seconds  = 60
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  scheduling_strategy                = "REPLICA"
  task_definition                    = "${var.task_name}:${aws_ecs_task_definition.minecraft.revision}"

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  deployment_controller {
    type = "ECS"
  }

  load_balancer {
    target_group_arn = var.minecraft_target_group_arn
    container_name   = var.container_name
    container_port   = 25565
  }

  load_balancer {
    target_group_arn = var.rcon_target_group_arn
    container_name   = var.container_name
    container_port   = 25575
  }


  network_configuration {
    assign_public_ip = true
    security_groups  = var.security_group_ids
    subnets          = var.subnet_ids
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-service"
    Environment = var.environment
  })
}
