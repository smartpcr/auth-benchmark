variable "subscription_id" {
    type = "string"
    description = "subscription used to provision azure resources"
}

variable "resource_group_name" {
    type = "string"
    description = "name of resource group"
}

variable "location" {
    type = "string"
    default = "westus2"
}

# key vault
variable "vault_name" {
    type = "string"
}

# storage
variable "storage_account" {
    type = "string"
}

variable "events_container" {
    type = "string"
}

variable "lease_container" {
    type = "string"
}

# event hub
variable "event_hub_namespace" {
    type = "string"
}

variable "event_hub_name" {
    type = "string"
}

variable "message_retention_in_days" {
    type = "string"
    default = 1
}

# iot hub
variable "iot_hub_name" {
    type = "string"
}

variable "iot_sku" {
    type = "string"
    default = "S1"
    description = "allowed values: B1, B2, B3, F1, S1, S2, S3"
}

variable "iot_partition_count" {
    type = "string"
    default = 10
    description = "The number of partitions of the backing Event Hub for device-to-cloud messages.  Default: 2."
}

variable "iot_units" {
    type = "string"
    default = 1
}

variable "iot_devices" {
    type = "list"
}
