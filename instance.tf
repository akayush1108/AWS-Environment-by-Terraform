
# Creating SSH Key
resource "aws_key_pair" "key-tf" {
  key_name   = "key-tf"
  public_key = file("${path.module}/id_rsa.pub")
}

# Creating VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Creating Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"
}

# Creating Private Subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1b"
}


# Creating Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Creating Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associating Route Table with Public Subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Creating Security Group for Public EC2 Instance
resource "aws_security_group" "public_ec2_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "public_ec2_sg"
  description = "Allow SSH, HTTP, and HTTPS inbound traffic and all outbound traffic"

  dynamic "ingress" {
    for_each = [80, 443]
    iterator = port
    content {
      description = "Allow inbound traffic"
      from_port   = port.value
      to_port     = port.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["111.93.177.58/32", "125.20.111.58/32"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Creating Security Group for Private EC2 Instance
resource "aws_security_group" "private_ec2_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "private_ec2_sg"
  description = "Allow all outbound traffic"

  ingress {
    description     = "Allow all inbound traffic from within the VPC"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["10.0.0.0/16"]
    security_groups = [aws_security_group.public_ec2_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Creating Security Group for RDS Instance
resource "aws_security_group" "rds_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "rds_sg"
  description = "Allow MySQL traffic only from private EC2 instances"

  ingress {
    description     = "Allow MySQL traffic from private EC2 instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.private_ec2_sg.id]
  }
}

# Creating First Instance in Public Subnet
resource "aws_instance" "public_instance" {
  ami                         = "ami-0f58b397bc5c1f2e8"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.key-tf.key_name
  vpc_security_group_ids      = [aws_security_group.public_ec2_sg.id]
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  tags = {
    Name = "public-instance"
  }
}

# Creating Second Instance in Private Subnet
resource "aws_instance" "private_instance" {
  ami                         = "ami-0f58b397bc5c1f2e8"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.key-tf.key_name
  vpc_security_group_ids      = [aws_security_group.private_ec2_sg.id]
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  tags = {
    Name = "private-instance"
  }
}

# Creating a DB Subnet Group for RDS
resource "aws_db_subnet_group" "default" {
  name = "my-db-subnet-group"
  subnet_ids = [
    aws_subnet.private.id,
    aws_subnet.private_b.id,
    # Add more subnets if needed to cover additional AZs
  ]

  tags = {
    Name = "My DB Subnet Group"
  }
}

# Creating RDS Instance in Private Subnets
resource "aws_db_instance" "default" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "mydb"
  username               = "admin"
  password               = "password123"
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.default.name

  tags = {
    Name = "my-rds-db"
  }
}
