terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS Region for this lab"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_1_cidr" {
  type    = string
  default = "10.0.11.0/24"
}

variable "private_subnet_2_cidr" {
  type    = string
  default = "10.0.12.0/24"
}

# -----------------------------------------------------------------------------
# 1. VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "LabVPC"
  }
}

# -----------------------------------------------------------------------------
# 2. Subnets in two Availability Zones
# -----------------------------------------------------------------------------
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet 1"
    Tier = "public"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet 2"
    Tier = "public"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.private_subnet_1_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "Private Subnet 1"
    Tier = "private"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "Private Subnet 2"
    Tier = "private"
  }
}

# -----------------------------------------------------------------------------
# 3. Internet Gateway and public route table
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "Lab-IGW"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "Public-RT"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Private subnets use a separate route table. It has only the VPC-local route;
# no NAT Gateway is created in this lab configuration.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "Private-RT"
  }
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# 4. Security groups
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "LabALBSecurityGroup"
  description = "Allow HTTP traffic to the application load balancer"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LabALBSecurityGroup"
  }
}

resource "aws_security_group" "app" {
  name        = "LabAppSecurityGroup"
  description = "Allow application traffic only from the load balancer"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "HTTP from the ALB security group"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LabAppSecurityGroup"
  }
}

resource "aws_security_group" "db" {
  name        = "LabDBSecurityGroup"
  description = "Allow MySQL/Aurora traffic from application servers"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "MySQL/Aurora from the application security group"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LabDBSecurityGroup"
  }
}

# -----------------------------------------------------------------------------
# 5. RDS DB subnet group only (NO Aurora/RDS database is created by this file)
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "lab" {
  name        = "labdbsubnetgroup"
  description = "Private database subnets for LabVPC"
  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  tags = {
    Name = "labdbsubnetgroup"
  }
}

# -----------------------------------------------------------------------------
# 6. ALB target group and Application Load Balancer
# The target group starts with no registered targets. Register EC2 instances
# manually or add them to Terraform later.
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name        = "ALBTargetGroup"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.lab.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "ALBTargetGroup"
  }
}

resource "aws_lb" "app" {
  name               = "LabAppALB"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb.id]
  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  tags = {
    Name = "LabAppALB"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the lab VPC"
  value       = aws_vpc.lab.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  value       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs for application/database resources"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

output "db_subnet_group_name" {
  description = "Select this subnet group when manually creating Aurora/RDS"
  value       = aws_db_subnet_group.lab.name
}

output "db_security_group_id" {
  description = "Attach this security group to Aurora/RDS"
  value       = aws_security_group.db.id
}

output "app_security_group_id" {
  description = "Attach this security group to application EC2 instances"
  value       = aws_security_group.app.id
}

output "alb_dns_name" {
  description = "DNS name of the internet-facing ALB"
  value       = aws_lb.app.dns_name
}

# -----------------------------------------------------------------------------
# 7. Security group for Systems Manager VPC endpoints
# -----------------------------------------------------------------------------

resource "aws_security_group" "ssm_endpoint" {
  name        = "LabVPCEndpointSG"
  description = "Allow HTTPS from application EC2 instances to SSM endpoints"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "HTTPS from application servers"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LabVPCEndpointSG"
  }
}

# -----------------------------------------------------------------------------
# 8. Systems Manager VPC Interface Endpoints
# -----------------------------------------------------------------------------

locals {
  ssm_endpoint_services = toset([
    "ssm",
    "ssmmessages",
    "ec2messages"
  ])
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.ssm_endpoint_services

  vpc_id              = aws_vpc.lab.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]
  security_group_ids  = [aws_security_group.ssm_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "Lab-${each.value}-Endpoint"
  }
}
