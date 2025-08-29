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

variable "gcp_zone" {
  description = "The zone where resources will be created."
  type        = string
  default     = "asia-south1-c"
}

variable "test_email" {
  description = "The email address for testing purposes."
  type        = string
  default     = "test@example.com"
}