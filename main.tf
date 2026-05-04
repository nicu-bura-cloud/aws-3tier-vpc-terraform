provider "aws" {
  region = "eu-central-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "vpc-nico" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "igw-nico" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-central-1a"
  tags                    = { Name = "subnet-pubblica-nico" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "rt-pubblica-nico" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "web_sg" {
  name        = "nico-web-sg"
  description = "Permetti SSH e HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "nico-web-sg" }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = "nico-udine-key"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Ciao NICO da AWS Francoforte con Amazon Linux" > /var/www/html/index.html
              EOF

  tags = { Name = "nico-primo-server" }
}

output "ip_pubblico_server" {
  value = aws_instance.web_server.public_ip
}
resource "aws_subnet" "privata_db" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b" # Zona diversa per Multi-AZ futuro

  tags = {
    Name = "nico-subnet-db"
  }
}
resource "aws_security_group" "rds" {
  name   = "nico-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id] # Solo la EC2 può entrare
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nico-rds-sg"
  }
}
resource "aws_db_instance" "mysql" {
  identifier             = "nico-db"
  allocated_storage      = 20 # 20GB gratis
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro" # Free Tier
  db_name                = "nicodb"
  username               = "admin"
  password               = "NicoDB2026!" # Cambiala dopo
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true  # Per distruggerlo senza problemi
  publicly_accessible    = false # SOLO da dentro la VPC
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.nico.name

  tags = {
    Name = "nico-mysql"
  }
}

resource "aws_db_subnet_group" "nico" {
  name       = "nico-db-subnet-group"
  subnet_ids = [aws_subnet.privata_db.id, aws_subnet.public.id] # RDS vuole 2 subnet

  tags = {
    Name = "nico-db-subnet-group"
  }
}
