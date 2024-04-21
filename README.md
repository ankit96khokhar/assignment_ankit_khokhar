# assignment_ankit_khokhar

- Once the cert is created, then alb_listener was updated along with port and protocol
- CIDR block 10.0.0.0/16 was used but we should check first in AWS console, if there is any VPC with this range already present then this should be changes. Similarly public and private subnets should also be changed
- Min, max and desired instances should be provided by the user. Default values have been given in variables.tf file
- Also, carefully check the values given in variables.tf and change it according to the need
