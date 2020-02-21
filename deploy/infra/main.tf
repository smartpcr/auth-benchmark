provider "azurerm" {
  subscription_id = "${var.subscription_id}"
}

data "azurerm_key_vault" "vault" {
  name                = "${var.vault_name}"
  resource_group_name = "${var.resource_group_name}"
}

# storage 
resource "azurerm_storage_account" "account" {
  name                     = "${var.storage_account}"
  resource_group_name      = "${var.resource_group_name}"
  location                 = "${var.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "events" {
  name                  = "${var.events_container}"
  storage_account_name  = "${azurerm_storage_account.account.name}"
  container_access_type = "private"
}

resource "azurerm_storage_container" "lease" {
  name                  = "${var.lease_container}"
  storage_account_name  = "${azurerm_storage_account.account.name}"
  container_access_type = "private"
}

# event hub
resource "azurerm_eventhub_namespace" "eventhub_namespace" {
  name                = "${var.event_hub_namespace}"
  resource_group_name = "${var.resource_group_name}"
  location            = "${var.location}"
  sku                 = "Basic"
}

resource "azurerm_eventhub" "eventhub" {
  name                = "${var.event_hub_name}"
  namespace_name      = "${azurerm_eventhub_namespace.eventhub_namespace.name}"
  resource_group_name = "${var.resource_group_name}"
  location            = "${var.location}"
  partition_count     = "${var.iot_partition_count}"
  message_retention   = "${var.message_retention_in_days}"
}

resource "azurerm_eventhub_authorization_rule" "eventhub_authkey" {
  resource_group_name = "${var.resource_group_name}"
  namespace_name      = "${azurerm_eventhub_namespace.eventhub_namespace.name}"
  eventhub_name       = "${azurerm_eventhub.eventhub.name}"
  name                = "acctest"
  send                = true
}

# iot hub
resource "azurerm_iothub" "iothub" {
  name                = "${var.iot_hub_name}"
  resource_group_name = "${var.resource_group_name}"
  location            = "${var.location}"
  sku                 = "${var.iot_sku}"

  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = "${azurerm_storage_account.account.primary_blob_connection_string}"
    name                       = "warmpath"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = "${azurerm_storage_container.events.name}"
    encoding                   = "Avro"
    file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }

  endpoint {
    type              = "AzureIotHub.EventHub"
    connection_string = "${azurerm_eventhub_authorization_rule.eventhub_authkey.primary_connection_string}"
    name              = "hotpath"
  }

  route {
    name           = "warmpath"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["warmpath"]
    enabled        = true
  }

  route {
    name           = "hotpath"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["hotpath"]
    enabled        = true
  }

  tags = {
    purpose = "testing"
  }
}
