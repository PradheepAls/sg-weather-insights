mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "ap-southeast-1" }
  }
}

variables {
  name        = "sgw-test"
  cidr_block  = "10.20.0.0/16"
  azs         = ["ap-southeast-1a", "ap-southeast-1b"]
  kms_key_arn = "arn:aws:kms:ap-southeast-1:111122223333:key/test"
}

run "three_tiers_two_azs_single_nat" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.app) == 2 && length(aws_subnet.data) == 2
    error_message = "Expected public, app and data subnets in each AZ."
  }
  assert {
    condition     = aws_subnet.app[0].cidr_block == "10.20.128.0/20" && aws_subnet.data[1].cidr_block == "10.20.208.0/20"
    error_message = "Subnet plan changed; this would force subnet replacement."
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Non-prod uses one shared NAT gateway."
  }
  assert {
    condition     = alltrue([for s in aws_subnet.data : s.map_public_ip_on_launch == false])
    error_message = "Data subnets must never assign public IPs."
  }
  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "VPC flow logs must capture all traffic."
  }
  assert {
    condition     = contains(keys(aws_vpc_endpoint.interface), "ssm") && contains(keys(aws_vpc_endpoint.interface), "secretsmanager")
    error_message = "SSM and Secrets Manager endpoints are required for private bootstrap."
  }
}

run "nat_per_az_for_prod" {
  command = plan
  variables {
    nat_gateway_per_az = true
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "Prod needs one NAT per AZ."
  }
}

run "rejects_too_small_vpc" {
  command = plan
  variables {
    cidr_block = "10.20.0.0/24"
  }
  expect_failures = [var.cidr_block]
}

run "rejects_single_az" {
  command = plan
  variables {
    azs = ["ap-southeast-1a"]
  }
  expect_failures = [var.azs]
}
