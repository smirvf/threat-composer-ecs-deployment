# CloudWatch Group Section
resource "aws_cloudwatch_log_group" "ecs_cw_group" {
  name              = "/ecs/threat-app"
  retention_in_days = 3
  #   setting retention to 3 days as more isn't required

  tags = {
    Name    = "ecs_cloudWatch_group"
    Project = "ecs"
  }
}

resource "aws_cloudwatch_dashboard" "ecs_cw_dashboard" {
  dashboard_name = "ecs-threat-app-dashboard"

  dashboard_body = jsonencode({
    start          = "-PT6H"
    periodOverride = "inherit"

    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          region = var.aws_region
          title  = "ECS Service CPU / Memory"
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.ecs_cluster.name, "ServiceName", aws_ecs_service.ecs_proj_service.name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.ecs_cluster.name, "ServiceName", aws_ecs_service.ecs_proj_service.name],
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          region = var.aws_region
          title  = "Recent logs (threat-app)"
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.ecs_cw_group.name}'\n| sort @timestamp desc\n| limit 50"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          region = var.aws_region
          title  = "ALB Requests / Latency / 5XX"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.ecs_alb_dimension, { stat : "Sum" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.ecs_alb_dimension, { stat : "Sum" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.ecs_alb_dimension, { stat : "Average" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.ecs_alb_dimension, { stat : "Minimum" }]
          ]
        }
      }
    ]
  })
}


# ECS Cluster Section
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs_cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# IAM Role Section
data "aws_iam_role" "ecs_task_execution_iam_role" {
  name = "ecsTaskExecutionRole"
}

data "aws_ecr_image" "ecr_image_name" {
  repository_name = var.ecs_ecr_repo_name
  most_recent     = true
}

# Task Definition Section
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "ecs_task_definition"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_iam_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "threat-app"
      image     = data.aws_ecr_image.ecr_image_name.image_uri
      essential = true
      cpu       = 512
      memory    = 1024

      portMappings = [
        {
          containerPort = 8080
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_cw_group.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "threat-app-task"
        }
      }
    }
  ])
  tags = {
    Name    = "ecs_task_definition"
    Project = "ecs"
  }
}

# ECS Service Section
resource "aws_ecs_service" "ecs_proj_service" {
  name            = "ecs_proj_service"
  launch_type     = "FARGATE"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = 2

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    security_groups  = [var.ecs_service_sg_id]
    subnets          = [var.ecs_subnet_private_2a_id, var.ecs_subnet_private_2b_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.ecs_alb_target_group_arn
    container_name   = "threat-app"
    container_port   = 8080
  }

  tags = {
    Name    = "ecs_service"
    Project = "ecs"
  }
}
