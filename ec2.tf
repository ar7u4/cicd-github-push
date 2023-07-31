terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.12.1"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ca-central-1"
}

# store the terraform state file in S3 bucketss
terraform {
  backend "s3" {
    bucket  = "ex2-terraform-state-buckets"
    key     = "build/terraform.tfstate"
    region  = "ca-central-1"
    profile = "default"
  }
}

# create VPC with Internet Gateway and public subnets
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "My VPC"
  }
}

resource "aws_internet_gateway" "my_internet_gateway" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "My Internet Gateway"
  }
}

resource "aws_subnet" "subnet_az1" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ca-central-1a"
  tags = {
    Name = "Subnet AZ1"
  }
}

resource "aws_subnet" "subnet_az2" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ca-central-1b"
  tags = {
    Name = "Subnet AZ2"
  }
}

# create public route table and associate with public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_internet_gateway.id
}

resource "aws_route_table_association" "public_subnet_association_az1" {
  subnet_id      = aws_subnet.subnet_az1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_association_az2" {
  subnet_id      = aws_subnet.subnet_az2.id
  route_table_id = aws_route_table.public_route_table.id
}

# create security group for the EC2 instance
resource "aws_security_group" "ec2_security_group" {
  name        = "ec2 security group"
  description = "allow access on ports 80 and 22"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "http access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2 security group"
  }
}

# use data source to get a registered Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

# launch the EC2 instance and install website
resource "aws_instance" "ec2_instance" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet_az1.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  user_data              = file("install_techmax.sh")

  tags = {
    Name = "techmax server"
  }
}

# create the load balancer with Internet-facing option
resource "aws_lb" "my_load_balancer" {
  name               = "my-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_security_group.id]
  subnets            = [aws_subnet.subnet_az1.id, aws_subnet.subnet_az2.id]

  enable_deletion_protection = false  # Optional: Set to true if you want to enable deletion protection

  tags = {
    Name = "My Load Balancer"
  }
}

# create the target group for the load balancer
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "My Target Group"
  }
}

# register the EC2 instance with the target group
resource "aws_lb_target_group_attachment" "ec2_attachment" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.ec2_instance.id
  port             = 80
}

# create a listener for the load balancer
resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}
output "load_balancer_dns" {
  value = aws_lb.my_load_balancer.dns_name
}
