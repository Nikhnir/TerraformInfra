provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {}
}

#This data source block is used to read the remote state file Layer1 and use all the outputs for Layer2
data "terraform_remote_state" "network_config" {
  backend = "s3"

  config = {
    bucket = var.remote_state_bucket
    key    = var.remote_state_key
    region = var.region
  }
}

resource "aws_security_group" "ec2_public_security_group" {
  name        = "EC2_Public-SG"
  description = "Internet reaching access for Ec2 instances"
  vpc_id      = data.terraform_remote_state.network_config.outputs.vpc_id  #remote state layer1

  ingress {
    from_port   = 80
    protocol    = "TCP"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    protocol    = "TCP"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Private sec group
resource "aws_security_group" "ec2_private_security_group" {
  name        = "Ec2-Private_SG"
  description = "Only allow public SG resources"
  vpc_id      = data.terraform_remote_state.network_config.outputs.vpc_id

  ingress {
    from_port       = 0
    protocol        = "-1"
    to_port         = 0
    security_groups = [aws_security_group.ec2_public_security_group.id] # allow traffic only from Public SG
  }

  ingress {
    from_port   = 80
    protocol    = "TCP"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow health checking for instances using this SG"
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb_security_group" {
  name        = "ELB-SG"
  description = "Elastic Load Balancer Security Group"
  vpc_id      = data.terraform_remote_state.network_config.outputs.vpc_id

  #allow everything as it is public facing load balancer
  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow web traffic to load balancer"
  }

  egress {
    from_port     = 0
    protocol      = "-1"
    to_port       = 0
    cidr_blocks   = ["0.0.0.0/0"]
  }
}

#Create IAM Role for EC2 to talk to autoscaling group
resource "aws_iam_role" "ec2_iam_role" {
  name               = "EC2-IAM-Role"
  assume_role_policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement" :
  [
    {
      "Effect" : "Allow",
      "Principal" : {
        "Service" : ["ec2.amazonaws.com", "application-autoscaling.amazonaws.com"]
      },
    "Action" : "sts:AssumeRole"
    }
  ]
}
EOF
}

#Create IAM Role Policy to attach to EC2
resource "aws_iam_role_policy" "ec2_iam_role_policy" {
  name = "EC2-IAM-Policy"
  role = aws_iam_role.ec2_iam_role.id
  policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "cloudwatch:*",
        "logs:*"
      ],
      "Resource":"*"
    }
  ]
}
  EOF
}

#IAM instance profile

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2-IAM-Instance-Profile"
  role = aws_iam_role.ec2_iam_role.name
}

#Data providerData source is used to refer to the internal resources of AWS.
#we are declaring data block because we dont want to use hard coded value in ec2 launch configuration
data "aws_ami" "launch_configuration_ami" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*"]
  }
}

resource "aws_launch_configuration" "ec2_private_launch_configuration" {
  image_id                    = data.aws_ami.launch_configuration_ami.id
  instance_type               = var.ec2_instance_type
  key_name                    = var.ec2_key_pair
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups             = [aws_security_group.ec2_private_security_group.id]

  user_data = <<EOF
  #!/bin/bash
  yum update -y
  yum install httpd -y
  service httpd start
  chkconfig http on
  export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
  echo "<html><body><h1>Hello from Production Backend at instance <b1>"$INSTANCE_ID"</b1></h1></body></html>" > /var/www/html/index.html
EOF
}

resource "aws_launch_configuration" "ec2_public_launch_configuration" {
  image_id                    = data.aws_ami.launch_configuration_ami.id
  instance_type               = var.ec2_instance_type
  key_name                    = var.ec2_key_pair
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups             = [aws_security_group.ec2_public_security_group.id]

  #We are printing EC2 instance id from ec2 metadata and adding to index.html
  user_data = <<EOF
    #!/bin/bash
  yum update -y
  yum install httpd -y
  service httpd start
  chkconfig http on
  export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
  echo "<html><body><h1>Hello from Production Webapp at instance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
EOF
}

#Configure Public facing Load Balancer front end
resource "aws_elb" "webapp_load_balancer" {
  name            = "Production-Webapp-LoadBalancer" #Internet facing
  internal        = false   #its public/internet facing so boolean value is false
  security_groups = [aws_security_group.elb_security_group.id]
  subnets = [
    data.terraform_remote_state.network_config.outputs.public_subnet_1_id,
    data.terraform_remote_state.network_config.outputs.public_subnet_2_id,
    data.terraform_remote_state.network_config.outputs.public_subnet_3_id
  ]
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  health_check {
    healthy_threshold   = 5
    interval            = 30
    target              = "HTTP:80/index.html"
    timeout             = 10
    unhealthy_threshold = 5
  }
}

#Backend load balancer for private instances
resource "aws_elb" "backend_load_balancer" {
  name            = "Production-Backend-Loadbalancer"
  internal        = true
  security_groups = [aws_security_group.elb_security_group.id]
  subnets = [
    data.terraform_remote_state.network_config.outputs.private_subnet_1_id,
    data.terraform_remote_state.network_config.outputs.private_subnet_2_id,
    data.terraform_remote_state.network_config.outputs.private_subnet_3_id,
  ]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    healthy_threshold   = 5
    interval            = 30
    target              = "HTTP:80/index.html"
    timeout             = 10
    unhealthy_threshold = 5
  }
}

#Private Autoscaling group
resource "aws_autoscaling_group" "ec2_private_autoscaling_group" {
  name                = "Production-Backend-Autoscaling-Group"
  vpc_zone_identifier = [
   data.terraform_remote_state.network_config.outputs.private_subnet_1_id,
   data.terraform_remote_state.network_config.outputs.private_subnet_2_id,
   data.terraform_remote_state.network_config.outputs.private_subnet_3_id
  ]
  max_size              = var.max_instance_size
  min_size              = var.min_instance_size
  launch_configuration  = aws_launch_configuration.ec2_private_launch_configuration.name
  health_check_type     = "ELB"
  load_balancers        = [aws_elb.backend_load_balancer.name]

  tag {
    key                 = "Name"
    propagate_at_launch = false
    value               = "Backend-EC2-Instance"
  }

  tag {
    key                 = "Type"
    propagate_at_launch = false
    value               = "Backend"
  }
}

#Public autoscaling group
resource "aws_autoscaling_group" "ec2_public_autoscaling_group" {
  name                = "Production-Webapp-Autoscaling-Group"
  vpc_zone_identifier = [
  data.terraform_remote_state.network_config.outputs.public_subnet_1_id,
  data.terraform_remote_state.network_config.outputs.public_subnet_2_id,
  data.terraform_remote_state.network_config.outputs.public_subnet_3_id
  ]
  max_size              = var.max_instance_size
  min_size              = var.min_instance_size
  launch_configuration  = aws_launch_configuration.ec2_public_launch_configuration.name
  health_check_type     = "ELB"
  load_balancers        = [aws_elb.webapp_load_balancer.name]

  tag {
    key                 = "Name"
    propagate_at_launch = false
    value               = "WebApp-Ec2_instance"
  }

  tag {
    key                 = "Type"
    propagate_at_launch = false
    value               = "Webapp"
  }
}

#We need Policy for actual autoscaling of EC2
resource "aws_autoscaling_policy" "webapp_production_scaling_policy" {
  autoscaling_group_name    = aws_autoscaling_group.ec2_public_autoscaling_group.name
  name                      = "Production-Webapp-Autoscaling-Policy"
  policy_type               = "TargetTrackingScaling"
  min_adjustment_magnitude  = 1

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 80.0
  }
}

resource "aws_autoscaling_policy" "Backend_production_scaling_policy" {
  autoscaling_group_name   = aws_autoscaling_group.ec2_private_autoscaling_group.name
  name                     = "Production-Backend-Autoscaling-Policy"
  policy_type              = "TargetTrackingScaling"
  min_adjustment_magnitude = 1

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 80.0
  }
}
