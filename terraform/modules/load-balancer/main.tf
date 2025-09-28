# =============================================================================
# Load Balancer Module
# =============================================================================

resource "aws_lb" "minecraft" {
  name               = "${var.project_name}-lb"
  internal           = var.internal
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-lb"
    Environment = var.environment
  })
}

resource "aws_lb_target_group" "minecraft" {
  name        = "${var.project_name}-tg"
  port        = 25565
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 60
    port                = "traffic-port"
    protocol            = "TCP"
    unhealthy_threshold = 2
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
  })
}

resource "aws_lb_target_group" "minecraft_rcon" {
  name        = "${var.project_name}-rcon-tg"
  port        = 25575
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 60
    port                = "traffic-port"
    protocol            = "TCP"
    unhealthy_threshold = 2
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-rcon-tg"
    Environment = var.environment
  })
}

resource "aws_lb_listener" "minecraft" {
  load_balancer_arn = aws_lb.minecraft.arn
  port              = "25565"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minecraft.arn
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-listener"
    Environment = var.environment
  })
}

resource "aws_lb_listener" "minecraft_rcon" {
  load_balancer_arn = aws_lb.minecraft.arn
  port              = "25575"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minecraft_rcon.arn
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-rcon-listener"
    Environment = var.environment
  })
}
