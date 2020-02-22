variable "subscription_id" {
  type = "string"
}

variable "tenant_id" {
  type = "string"
}

variable "env_name" {
  type = "string"
}

variable "space_name" {
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
variable "provision_storage_account" {
  type = "string"
}

variable "artifact_container" {
  type = "string"
  default = "artifacts"
}

variable "telemetry_storeage_account" {
  type = "string"
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

# cosmos db
variable "cosmosdb_account" {
  type = "string"
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

# iot tool
variable "git_root_folder" {
  type = "string"
}

variable "app_relative_folder" {
  type = "string"
}