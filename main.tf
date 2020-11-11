terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Get latest Ubuntu image
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

# Create a VPC
resource "aws_vpc" "cloudhsm_v2_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "example-aws_cloudhsm_v2_cluster"
  }
}

# Create a subnet inside VPC
resource "aws_subnet" "cloudhsm_v2_subnets" {
  vpc_id                  = aws_vpc.cloudhsm_v2_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "example-aws_cloudhsm_v2_cluster"
  }
}

# Create Security Group for SSH
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic; Allow all outbound traffic"
  vpc_id      = aws_vpc.cloudhsm_v2_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create Internet Gateway for VPC
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.cloudhsm_v2_vpc.id
}

# Create default route table for VPC
resource "aws_default_route_table" "route_table" {
  default_route_table_id = aws_vpc.cloudhsm_v2_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = {
    Name = "Default route table"
  }
}


# Create HSM cluster
resource "aws_cloudhsm_v2_cluster" "cloudhsm_v2_cluster" {
  hsm_type   = "hsm1.medium"
  subnet_ids = [aws_subnet.cloudhsm_v2_subnets.id]

  tags = {
    Name = "example-aws_cloudhsm_v2_cluster"
  }
}

# Create HSM
resource "aws_cloudhsm_v2_hsm" "cloudhsm_v2_hsm" {
  subnet_id  = aws_subnet.cloudhsm_v2_subnets.id
  cluster_id = aws_cloudhsm_v2_cluster.cloudhsm_v2_cluster.cluster_id
}

# Generate SSH key
resource "tls_private_key" "vault" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS Key Pair
resource "aws_key_pair" "vault" {
  key_name   = "vault-key"
  public_key = tls_private_key.vault.public_key_openssh
}

# Create Vault EC2 instance
resource "aws_instance" "vault" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.cloudhsm_v2_subnets.id
  vpc_security_group_ids = [aws_cloudhsm_v2_cluster.cloudhsm_v2_cluster.security_group_id, aws_security_group.allow_ssh.id]

  key_name = aws_key_pair.vault.key_name

  tags = {
    Name = "example-aws_cloudhsm_v2_cluster"
  }
}

# Create private key file locally
resource "local_file" "private_key" {
  content  = tls_private_key.vault.private_key_pem
  filename = "vault-key.pem"
}

output "hsm_cluster_id" {
  value = aws_cloudhsm_v2_cluster.cloudhsm_v2_cluster.cluster_id
}

output "ec2_public_ip" {
  value = aws_instance.vault.public_ip
}