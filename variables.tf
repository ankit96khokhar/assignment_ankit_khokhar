variable "region" {
  type        = string
  description = "The AWS region"
  default     = "us-east-1"
}

variable "vpc_name" {
  type        = string
  description = "The name of the VPC"
  default     = "assignment-vpc"
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR for the VPC"
  default     = "10.0.0.0/16"
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  type        = list(string)
  description = "Public subnets"
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "igw_name" {
  type        = string
  description = "The name of the Internet Gateway."
  default     = "assignment-igw"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 5
}

variable "desired_capacity" {
  type    = number
  default = 3
}