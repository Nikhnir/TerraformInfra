provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {}
}

resource "aws_vpc" "production-vpc" {
  cidr_block            = var.vpc_cidr
  enable_dns_hostnames  = true

  tags = {
   Name = "Production-VPC"
  }
}

resource "aws_subnet" "public-subnet-1" {
  cidr_block        = var.public_subnet_1_cidr
  vpc_id            = aws_vpc.production-vpc.id
  availability_zone = "us-east-2a"

  tags = {
    Name = "Public-Subnet-1"
  }
}

resource "aws_subnet" "public-subnet-2" {
  cidr_block        = var.public_subnet_2_cidr
  vpc_id            = aws_vpc.production-vpc.id
  availability_zone = "us-east-2b"

  tags = {
    Name = "Public-Subnet-2"
  }
}


resource "aws_subnet" "public-subnet-3" {
  cidr_block        = var.public_subnet_3_cidr
  vpc_id            = aws_vpc.production-vpc.id
  availability_zone = "us-east-2c"

  tags = {
    Name = "Public-Subnet-3"
  }
}

resource "aws_subnet" "private-subnet-1" {
  cidr_block        = var.private_subnet_1_cidr
  vpc_id            = aws_vpc.production-vpc.id
  availability_zone = "us-east-2a"

  tags = {
    Name = "Private-Subnet-1"
  }
}

resource "aws_subnet" "private-subnet-2" {
  cidr_block = var.private_subnet_2_cidr
  vpc_id = aws_vpc.production-vpc.id
  availability_zone = "us-east-2b"

  tags = {
    Name = "Private-Subnet-2"
  }
}

resource "aws_subnet" "private-subnet-3" {
  cidr_block        = var.private_subnet_3_cidr
  vpc_id            = aws_vpc.production-vpc.id
  availability_zone = "us-east-2c"

  tags = {
    Name = "Private-Subnet-3"
  }
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.production-vpc.id

  tags = {
   Name = " Public Route Table"
  }
}

resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.production-vpc.id

  tags = {
    Name = "Private Route Table"
  }
}

resource "aws_route_table_association" "public-route-table-association-1" {
  route_table_id  = aws_route_table.public-route-table.id
  subnet_id       = aws_subnet.public-subnet-1.id

}

resource "aws_route_table_association" "public-route-table-association-2" {
  route_table_id  = aws_route_table.public-route-table.id
  subnet_id       = aws_subnet.public-subnet-2.id
}

resource "aws_route_table_association" "public-route-table-association-3" {
  route_table_id  = aws_route_table.public-route-table.id
  subnet_id       = aws_subnet.public-subnet-3.id
}

resource "aws_route_table_association" "private-route-table-association-1" {
  route_table_id  = aws_route_table.private-route-table.id
  subnet_id       = aws_subnet.private-subnet-1.id
}

resource "aws_route_table_association" "private-route-table-association-2" {
  route_table_id  = aws_route_table.private-route-table.id
  subnet_id       = aws_subnet.private-subnet-2.id
}

resource "aws_route_table_association" "private-route-table-association-3" {
  route_table_id  = aws_route_table.private-route-table.id
  subnet_id       = aws_subnet.private-subnet-3.id
}

resource "aws_eip" "elastic-ip-for-natgw" {
  vpc                       = true
  associate_with_private_ip = "10.0.0.5" #associate private ip  for Elastic ip
  tags = {
    Name              = "Production-EIP"
    }
}

resource "aws_nat_gateway" "nat-gateway" {
  allocation_id = aws_eip.elastic-ip-for-natgw.id  #id for elastic ip
  subnet_id     = aws_subnet.public-subnet-1.id    #associate with public subnet
  tags = {
    Name        = "Prod-Nat-Gateway"
  }
  depends_on    = [aws_eip.elastic-ip-for-natgw]        #after creation of EIP , Nat will be created.
}

resource "aws_route" "nat-gw-route" {
  nat_gateway_id          = aws_nat_gateway.nat-gateway.id
  route_table_id          = aws_route_table.private-route-table.id
  destination_cidr_block  = "0.0.0.0/0"
}

resource "aws_internet_gateway" "prod-igw" {
  vpc_id    = aws_vpc.production-vpc.id
  tags = {
    Name    = "Prod-IGW"
  }
}

resource "aws_route" "public-route-igw-route" {
  route_table_id          = aws_route_table.public-route-table.id
  gateway_id              = aws_internet_gateway.prod-igw.id
  destination_cidr_block  = "0.0.0.0/0"
}




