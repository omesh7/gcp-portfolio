variable "gcp_project_id" {
  description = "The ID of the GCP project where resources will be created."
  type        = string
  sensitive   = true

}

variable "gcp_region" {
  description = "The region where resources will be created."
  type        = string
  default     = "asia-south1"
}


variable "gcp_account_id" {
  description = "The ID of the GCP billing account."
  type        = string
  sensitive   = true

}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "day8-${random_id.suffix.hex}"
}

variable "ssh_user" {
  description = "SSH username for connecting to instances"
  type        = string
  default     = "gcp-user"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "./ssh-key.pub"
}
