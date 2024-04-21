provider "aws" {
  region = var.region
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnets[0]

  tags = {
    Name = "private-subnet"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.public_subnets[0]

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = var.igw_name
  }
}

resource "aws_route_table" "public_RT" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "publicRTassociation" {
  subnet_id = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_RT.id
}

resource "aws_security_group" "load_balancers_sg" {
  name_prefix = "load-balancers"
  description = "Allow inbound traffic on ports 80 and 443 for the load balancers"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
}

resource "aws_security_group" "private_instances_sg" {
  name_prefix = "private-instances"
  description = "Allow inbound traffic on ports 22, 80, and 443 for the instances in the private subnets"
  vpc_id      = aws_vpc.vpc.id

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
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
}

resource "aws_security_group" "public_instances_sg" {
  name_prefix = "public-instances"
  description = "Allow inbound traffic on port 22 for the instances in the public subnets"
  vpc_id      = aws_vpc.vpc.id

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
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }
}

#Create ALB
resource "aws_alb" "alb" {
  name            = "assignment_alb"
  internal        = false
  security_groups = [aws_security_group.load_balancers_sg.id]
  subnets         = aws_subnet.public_subnet.*.id

  tags = {
    Name = "assignment_alb"
  }
}

resource "aws_alb_target_group" "tg" {
  name     = "assignment_tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "assignment_tg"
  }
}

resource "aws_alb_listener" "alb_listener" {
  load_balancer_arn = aws_alb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    target_group_arn = aws_alb_target_group.tg.arn
    type             = "forward"
  }
}

resource "aws_alb_target_group_attachment" "alb_tg_attach" {
  count              = length(aws_autoscaling_group.asg.instances)
  target_group_arn   = aws_alb_target_group.tg.arn
  target_id          = aws_autoscaling_group.asg.instances[count.index]
  port               = 80
}

data "aws_ami_filter" "amazon_linux_2" {
  name   = "name"
  values = ["amzn2-ami-hvm-*-x86_64-ebs"]
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = [data.aws_ami_filter.amazon_linux_2.values[0]]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  owners = ["amazon"]
}

#Generate KMS key for encryption
resource "aws_kms_key" "kms_ec2" {
  description             = "KMS key for instances"
}

resource "aws_kms_alias" "kms_ec2" {
  name          = "assignment"
  target_key_id = aws_kms_key.kms_ec2.key_id
}

resource "aws_launch_configuration" "launch_config" {
  name_prefix   = "private-instances-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.private_instances_sg.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 6
      volume_type = "gp2"
      encrypted   = true
      kms_key_id  = aws_kms_key.kms_ec2.arn
    }
  }

  block_device_mappings {
    device_name = "/dev/xvdb"
    ebs {
      volume_size = 4
      volume_type = "gp2"
      encrypted   = true
      kms_key_id  = aws_kms_key.kms_ec2.arn
    }
  }

  user_data = <<-EOF
              #!/bin/bash
              mkdir /var/log
              mount /dev/xvdb /var/log
              sudo yum update -y
              sudo yum install -y httpd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              sudo yum install -y ansible
              ansible-playbook -i ansible/hosts ansible/playbook.yml
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "asg" {
  name                 = "assignment_asg"
  launch_configuration = aws_launch_configuration.launch_config.name
  min_size             = 2
  max_size             = 5
  desired_capacity     = 3
  vpc_zone_identifier   = aws_subnet.private_subnet.*.id

  tag {
    Name                 = "assignment_asg"
  }
}resource "aws_autoscaling_group" "asg" {
  name                 = "assignment_asg"
  launch_configuration = aws_launch_configuration.launch_config.name
  min_size             = var.min_size
  max_size             = var.max_size
  desired_capacity     = var.desired_capacity
  vpc_zone_identifier   = aws_subnet.private_subnet.*.id

  tag {
    Name                 = "assignment_asg"
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name               = "test.example.com"
  validation_method         = "DNS"
  subject_alternative_names = ["*.test.example.com"]

  lifecycle {
    create_before_destroy = true
  }
}

# Create a private hosted zone in Route 53 for the VPC
resource "aws_route53_zone" "private" {
  name = "test.example.com"

  vpc {
    vpc_id = aws_vpc.vpc.id
  }
}

resource "aws_route53_record" "private" {
  name    = "test.example.com"
  type    = "A"
  zone_id = aws_route53_zone.private.zone_id

  alias {
    name                   = aws_alb.alb.dns_name
    zone_id                = aws_alb.alb.zone_id
  }
}

resource "aws_route53_health_check" "route53_health" {
  fqdn              = "test.example.com"
  type              = "HTTP"
  port              = "80"
  resource_path     = "/"
  failure_threshold = "5"
  request_interval  = "30"
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_alarm" {
  alarm_name          = "health-check-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "This alarm triggers when the Route 53 health check for test.example.com fails"
  dimensions = {
    HealthCheckId = aws_route53_health_check.route53_health.id
  }
}