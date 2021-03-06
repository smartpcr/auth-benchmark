terraform {
  backend "azurerm" {}
}

provider "azurerm" {
  version = "~>1.44"
}

provider "null" {
  version = "~>2.1.2"
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}"
  location = "${var.location}"
}

# storage
resource "azurerm_storage_account" "provision_store" {
  name                     = "${var.provision_storage_account}"
  resource_group_name      = "${azurerm_resource_group.rg.name}"
  location                 = "${azurerm_resource_group.rg.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "artifacts" {
  name                  = "${var.artifact_container}"
  storage_account_name  = "${azurerm_storage_account.provision_store.name}"
  container_access_type = "private"
}

resource "azurerm_storage_account" "telemetry_store" {
  name                     = "${var.telemetry_storage_account}"
  resource_group_name      = "${azurerm_resource_group.rg.name}"
  location                 = "${azurerm_resource_group.rg.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "events" {
  name                  = "${var.events_container}"
  storage_account_name  = "${azurerm_storage_account.telemetry_store.name}"
  container_access_type = "private"
}

resource "azurerm_storage_container" "anomalies" {
  name                  = "${var.anomalies_container}"
  storage_account_name  = "${azurerm_storage_account.telemetry_store.name}"
  container_access_type = "private"
}

resource "azurerm_storage_container" "alerts" {
  name                  = "${var.alerts_container}"
  storage_account_name  = "${azurerm_storage_account.telemetry_store.name}"
  container_access_type = "private"
}

# app insights
resource "azurerm_application_insights" "app_insights" {
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"
  name                = "${var.app_insights_name}"
  application_type    = "web"
}

resource "azurerm_user_assigned_identity" "app_identity" {
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"

  name = "${var.app_identity_name}"
}

resource "azurerm_app_service_plan" "svcplan" {
  name                = "${var.service_plan_name}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"

  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_function_app" "function_app" {
  name                      = "${var.function_app_name}"
  location                  = "${azurerm_resource_group.rg.location}"
  resource_group_name       = "${azurerm_resource_group.rg.name}"
  app_service_plan_id       = "${azurerm_app_service_plan.svcplan.id}"
  storage_connection_string = "${azurerm_storage_account.provision_store.primary_connection_string}"
  version                   = "~3"

  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY = "${azurerm_application_insights.app_insights.instrumentation_key}"
    VaultName                      = "${var.vault_name}"
    StorageAccount                 = "${var.telemetry_storage_account}"
    EventsContainer                = "${var.events_container}"
    AnomaliesContainer             = "${var.anomalies_container}"
    AlertsContainer                = "${var.alerts_container}"
    CosmosDbAccount                = "${var.cosmosdb_account}"
    WEBSITE_RUN_FROM_PACKAGE       = "1"
  }

  identity {
    type = "SystemAssigned, UserAssigned"
    identity_ids = [
      "${azurerm_user_assigned_identity.app_identity.id}" # only system-assigned identity works!!
    ]
  }

  depends_on = [
    "azurerm_application_insights.app_insights",
    "azurerm_user_assigned_identity.app_identity"
  ]
}

resource "null_resource" "assign_msi_access" {
  count = "${var.function_app_name != "" && var.telemetry_storage_account != "" ? 1 : 0}"

  provisioner "local-exec" {
    # multiline syntax only support within module
    command = "pwsh ./GrantFunctionAppMsiPermissions.ps1 -AppName ${var.function_app_name} -GitRootFolder \"${var.git_root_folder}\" -ResourceGroupName ${azurerm_resource_group.rg.name} -SubscriptionId ${var.subscription_id} -StorageAccountName ${var.telemetry_storage_account}"
  }

  triggers = {
    function_app_name         = "${var.function_app_name}"
    telemetry_storage_account = "${var.telemetry_storage_account}"
  }

  depends_on = ["azurerm_function_app.function_app"]
}

resource "null_resource" "publish_function_app" {
  count = "${var.function_app_name != "" && var.telemetry_storage_account != "" ? 1 : 0}"

  provisioner "local-exec" {
    # multiline syntax only support within module
    command = "pwsh ./PublishFunctionApp.ps1 -AppName ${var.function_app_name} -GitRootFolder \"${var.git_root_folder}\" -AppRelativeFolder \"${var.app_relative_folder}\""
  }

  triggers = {
    function_app_name = "${var.function_app_name}"
    function_app_hash = "${var.function_app_hash}"
  }

  depends_on = [
    "azurerm_function_app.function_app",
    "null_resource.assign_msi_access"
  ]
}
