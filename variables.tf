variable "project_id" {
  type = string
}
variable "region" {
  type = string
}
variable "zone" {
  type = string
}

variable "vpc_network_name" {
  type = string
}
variable "static_ip_name" {
  type = string
}

variable "named_private_ip_name" {
  type        = string
  description = "The name for the named_private_ip"
}
variable "named_private_ip" {
  type        = string
  description = "This is the IP address by which Cloud Build talks to proxy server."
}
variable "named_private_ip_prefix_length" {
  type        = string
  description = "Determines the range for named_private_ip. Example: 24"
}

variable "private_worker_pool_name" {
  type = string
}

variable "vm_subnet_range" {
  type = string
}
variable "vm_ip_address" {
  type        = string
  description = "Private IP address for the Proxy Server"
}
