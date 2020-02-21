variable "subscription_id" {
  type = "string"
}

variable "tenant_id" {
  type = "string"
}


variable "resource_group_name" {
  type = "string"
}

variable "location" {
  type = "string"
}

variable "storage_account" {
  type = "string"
}

variable "artifact_container" {
  type = "string"
  default = "artifacts"
}

variable "service_plan_name" {
  type = "string"
  default = "service_plan"
}

variable "function_app_name" {
  type = "string"
  default = "function-app"
}

variable "app_identity_name" {
  type = "string"
}

variable "app_insights_name" {
  type = "string"
}