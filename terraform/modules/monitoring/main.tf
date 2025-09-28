# =============================================================================
# Monitoring Module
# =============================================================================

resource "aws_cloudwatch_dashboard" "minecraft" {
  count           = var.enable_dashboard ? 1 : 0
  dashboard_name  = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", var.service_name, "ClusterName", var.cluster_name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Minecraft Server Metrics"
          period  = 300
        }
      }
    ]
  })
}

# ECSサービス停止アラーム
resource "aws_cloudwatch_metric_alarm" "ecs_service_stopped" {
  alarm_name          = "${var.project_name}-ecs-service-stopped"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors ECS service running count"
  alarm_actions       = var.enable_alerts ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    ServiceName = var.service_name
    ClusterName = var.cluster_name
  }

  tags = {
    Name        = "${var.project_name}-ecs-service-stopped-alarm"
    Environment = var.environment
  }
}

# CPU使用率アラーム
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.project_name}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = var.enable_alerts ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    ServiceName = var.service_name
    ClusterName = var.cluster_name
  }

  tags = {
    Name        = "${var.project_name}-ecs-cpu-high-alarm"
    Environment = var.environment
  }
}

# メモリ使用率アラーム
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${var.project_name}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors ECS memory utilization"
  alarm_actions       = var.enable_alerts ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    ServiceName = var.service_name
    ClusterName = var.cluster_name
  }

  tags = {
    Name        = "${var.project_name}-ecs-memory-high-alarm"
    Environment = var.environment
  }
}

# SNSトピック（アラート有効時のみ）
resource "aws_sns_topic" "alerts" {
  count = var.enable_alerts ? 1 : 0
  name  = "${var.project_name}-alerts"

  tags = {
    Name        = "${var.project_name}-alerts"
    Environment = var.environment
  }
}
