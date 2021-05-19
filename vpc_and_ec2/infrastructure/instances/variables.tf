variable "region" {
  default = "us-east-2"
}

variable "remote_state_bucket" {
  description = "Bucket name for Layer 1 remote state"
}

variable "remote_state_key" {
  description = "Key name for Layer 1 remote state"
}

variable "ec2_instance_type" {
  description = "Instance type of EC2 to launch"
}

variable "ec2_key_pair" {
  default = "myec2keypair"
  description = "KeyPair to connect to the EC2"
}

variable "max_instance_size" {
  description = "Maximum number of instances to Launch"
}

variable "min_instance_size" {
  description = "Minimum number of instances to Launch"
}