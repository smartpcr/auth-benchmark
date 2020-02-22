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

variable "vault_name" {
  type = "string"
}

# storage
variable "storage_account" {
  type = "string"
}

variable "artifact_container" {
  type = "string"
  default = "artifacts"
}

variable "events_container" {
  type = "string"
  default = "events"
}

variable "anomalies_container" {
  type = "string"
  default = "anomalies"
}

variable "alerts_container" {
  type = "string"
  default = "alerts"
}

# function 
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