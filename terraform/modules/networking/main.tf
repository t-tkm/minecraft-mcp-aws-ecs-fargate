# =============================================================================
# Networking Module
# =============================================================================

# 現在のIPアドレスを取得（手動設定されていない場合のみ）
data "http" "my_ip" {
  count = var.my_ip == "" ? 1 : 0
  url   = "https://ipv4.icanhazip.com"
}

# 使用するIPアドレスを決定
locals {
  # 手動設定がある場合はそれを使用、なければ自動検出、それも失敗した場合は0.0.0.0/0
  allowed_ip = var.my_ip != "" ? var.my_ip : (
    var.my_ip == "" && length(data.http.my_ip) > 0 ? "${chomp(data.http.my_ip[0].response_body)}/32" : "0.0.0.0/0"
  )
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  })
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "minecraft" {
  name        = "${var.project_name}-minecraft-sg"
  description = "Security group for Minecraft server"
  vpc_id      = aws_vpc.main.id

  # Minecraft server port (25565) - from load balancer only (NLB doesn't use security groups)
  ingress {
    description = "Minecraft server access from load balancer"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]  # Allow from VPC CIDR
  }

  # RCON port (25575) - from load balancer only (NLB doesn't use security groups)
  ingress {
    description = "Minecraft RCON access from load balancer"
    from_port   = 25575
    to_port     = 25575
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]  # Allow from VPC CIDR
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-minecraft-sg"
    Environment = var.environment
  })
}

resource "aws_security_group" "ec2_proxy" {
  name        = "${var.project_name}-ec2-proxy-sg"
  description = "Security group for EC2 proxy"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS access for port forwarding from my IP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.allowed_ip]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-ec2-proxy-sg"
    Environment = var.environment
  })
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS access from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.minecraft.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-efs-sg"
    Environment = var.environment
  })
}

# Load balancer security group - REMOVED (not needed for NLB)
