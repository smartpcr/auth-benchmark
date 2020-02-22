resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}"
  location = "${var.location}"
}

# storage
resource "azurerm_storage_account" "store" {
  name                     = "${var.storage_account}"
  resource_group_name      = "${azurerm_resource_group.rg.name}"
  location                 = "${azurerm_resource_group.rg.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "artifacts" {
  name                  = "${var.artifact_container}"
  storage_account_name  = "${azurerm_storage_account.store.name}"
  container_access_type = "private"
}

resource "azurerm_application_insights" "app_insights" {
  resource_group_name      = "${azurerm_resource_group.rg.name}"
  location                 = "${azurerm_resource_group.rg.location}"
  name                            = "${var.app_insights_name}"
  application_type = "web"
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
  storage_connection_string = "${azurerm_storage_account.store.primary_connection_string}"
  runtime = "~3"

  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY = "${azurerm_application_insights.app_insights.instrumentation_key}"
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      "${azurerm_user_assigned_identity.app_identity.id}"
    ]
  }

  depends_on = [
    "azurerm_application_insights.app_insights",
    "azurerm_user_assigned_identity.app_identity"
  ]
}