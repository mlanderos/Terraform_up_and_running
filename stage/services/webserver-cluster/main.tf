provider "aws" {
    region = "us-east-2"
}

resource "aws_launch_configuration" "example" {
    image_id          = "ami-0c55b159cbfafe1f0"
    instance_type = "t2.micro"
    security_groups = [aws_security_group.instance.id]

    user_data = <<-EOF
                #!/bin/bash
                echo "Hello, World" > index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF

    # Required when using a launch configuration with an auto scaling group.
    # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
    lifecycle {
        create_before_destroy = true
    }
}

data "aws_vpc" "default" {
    default = true
}

data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}

resource "aws_autoscaling_group" "example" {
    launch_configuration  = aws_launch_configuration.example.name
    vpc_zone_identifier   = data.aws_subnet_ids.default.ids

    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"

    min_size = 2
    max_size = 10

    tag {
        key                 = "Name"
        value               = "terraform-asg-example"
        propagate_at_launch = true
    }
}

resource "aws_security_group" "instance" {
    name = "terraform-example-instance"

    ingress {
        from_port   = var.server_port
        to_port     = var.server_port
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# create the ALB inself using hte aws_lb resource
resource "aws_lb" "example" {
    name               = "terraform-asg-example"
    load_balancer_type = "application"
    subnets            = data.aws_subnet_ids.default.ids
    security_groups    = [aws_security_group.alb.id]
}

# define a listner for the ALB using the aws_lb_listener resource
resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn
    port              = 80
    protocol          = "HTTP"

    #by default, return a simple 404 page
    default_action {
        type = "fixed-response"

        fixed_response {
            content_type = "text/plain"
            message_body = "404: page not found"
            status_code  = 404
        }
    }
}

resource "aws_security_group" "alb" {
    name = "terraform-example-alb"

    #allow inbound http requests
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # allow all outbound requests
    egress {
        from_port  = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_lb_target_group" "asg" {
    name          = "terraform-asg-example"
    port          = var.server_port
    protocol      = "HTTP"
    vpc_id        = data.aws_vpc.default.id

    health_check {
        path                = "/"
        protocol            = "HTTP"
        matcher             = "200"
        interval            = 15
        timeout             = 3
        healthy_threshold   = 2
        unhealthy_threshold = 2
    }
}

resource "aws_lb_listener_rule" "asg" {
    listener_arn = aws_lb_listener.http.arn
    priority     = 100

    condition {
        path_pattern {
            values = ["*"]
        }
    }

    action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.asg.arn
    }
}

# add backend configuration
provider "aws" {
    region = "us-east-2"
}

resource "aws_s3_bucket" "terraform_state" {
    bucket = "terraform-up-and-running-state-mlanderos"

    # Prevent accidental deletion of this S3 bucket
    lifecycle {
        prevent_destroy = true
    }

    #Enable versioning so we can see the full version history of our state files
    versioning {
        enabled = true
    }

    #enable server-side encryption by default
    server_side_encryption_configuration {
        rule {
            apply_server_side_encryption_by_default {
                sse_algorithm = "AES256"
            }
        }
    }
}

resource "aws_dynamodb_table" "terraform_locks" {
    name         = "terraform-up-and-running-locks"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "LockID"

    attribute {
        name = "LockID"
        type = "S"
    }
}

terraform {
    backend "s3" {
        bucket = "terraform-up-and-running-state-mlanderos"
        key    = "stage/services/webserver-cluster/terraform.tfstate"
        region = "us-east-2"

        dynamodb_table = "terraform-up-and-running-locks"
        encrypt        = true
    }
}

resource "aws_instance" "example" {
    ami            = "ami-0c55b159cbfafe1f0"
    instance_type  = "t2.micro"
}

terraform {
    backend "s3" {
        bucket         = "terraform-up-and-running-state-mlanderos"
        key            = "workspaces-example/terraform.tfstate"
        region         = "us-east-2"

        dynamodb_table = "terraform-up-and-running-locks"
        encrypt        = true
    }
}
