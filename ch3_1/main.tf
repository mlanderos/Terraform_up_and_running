provider "aws" {
    region = "us-east-2"
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