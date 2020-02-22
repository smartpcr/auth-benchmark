terraform {
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = "${var.subscription_id}"
  version         = "~>1.44"
}

provider "null" {
  version = "~>2.1.2"
}

data "azurerm_key_vault" "vault" {
  name                = "${var.vault_name}"
  resource_group_name = "${var.resource_group_name}"
}

resource "null_resource" "cosmosdb_account" {
  count = "${var.cosmos_db_account != "" && var.resource_group_name != "" ? 1 : 0}"

  provisioner "local-exec" {
    command = <<-EOT
      "pwsh ${path.module}/EnsureCosmosDbAccount.ps1 \
      -Account ${var.cosmos_db_account} \
      -SubscriptionId \"${var.cosmosdb_subscription_id}\" \
      -ResourceGroupName ${var.resource_group_name} \
      -Consistency ${var.consistency_level} \
      -Location ${var.location}"
    EOT
  }

  triggers = {
    cosmos_db_account        = "${var.cosmos_db_account}"
    cosmosdb_subscription_id = "${var.cosmosdb_subscription_id}"
    resource_group_name      = "${var.resource_group_name}"
    consistency_level        = "${var.consistency_level}"
  }
}

resource "null_resource" "create_cosmosdb_sql_collections" {
  count = "${var.cosmos_db_settings != "" ? 1 : 0}"

  provisioner "local-exec" {
    command = <<-EOT
      "pwsh ${path.module}/EnsureCosmosDbCollections.ps1 \
      -AccountName ${var.cosmos_db_account} \
      -SubscriptionId \"${var.cosmosdb_subscription_id}\" \
      -ResourceGroupName ${var.resource_group_name} \
      -DbCollectionSettings \"${var.cosmos_db_settings}\""
    EOT
  }

  triggers = {
    cosmos_db_account        = "${var.cosmos_db_account}"
    cosmosdb_subscription_id = "${var.cosmosdb_subscription_id}"
    cosmos_db_settings       = "${var.cosmos_db_settings}"
  }

  depends_on = ["null_resource.cosmosdb_account"]
}

resource "null_resource" "store_auth_key" {
  count = "${var.cosmos_db_account != "" && var.resource_group_name != "" && var.vault_name != "" ? 1 : 0}"

  provisioner "local-exec" {
    command = <<-EOT
      "pwsh ${path.module}/StoreCosmosDbAuthKey.ps1 \
      -DbAccount ${var.cosmos_db_account} \
      -SubscriptionId \"${var.cosmosdb_subscription_id}\" \
      -ResourceGroupName ${var.resource_group_name} \
      -VaultName \"${var.vault_name}\" \
      -VaultSubscriptionId \"${var.vault_subscription_id}\""
    EOT
  }

  triggers = {
    cosmos_db_account        = "${var.cosmos_db_account}"
    cosmosdb_subscription_id = "${var.cosmosdb_subscription_id}"
    resource_group_name      = "${var.resource_group_name}"
    vault_name               = "${var.vault_name}"
    vault_subscription_id    = "${var.vault_subscription_id}"
  }

  depends_on = ["null_resource.cosmosdb_account"]
}


