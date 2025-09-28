# =============================================================================
# EC2 Module
# =============================================================================

resource "aws_key_pair" "minecraft_proxy" {
  key_name   = "${var.project_name}-proxy-key"
  public_key = file(var.ssh_public_key_path)

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-proxy-key"
    Environment = var.environment
  })
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-ec2-ssm-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-ec2-ssm-profile"
    Environment = var.environment
  })
}

resource "aws_instance" "minecraft_proxy" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.minecraft_proxy.key_name
  vpc_security_group_ids = [var.security_group_id]
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  monitoring = false

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y htop
    echo "EC2 proxy instance ready for Session Manager port forwarding"
  EOF
  )

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-proxy"
    Environment = var.environment
  })
}

resource "aws_eip" "minecraft_proxy" {
  instance = aws_instance.minecraft_proxy.id
  vpc      = true

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-proxy-eip"
    Environment = var.environment
  })
}
