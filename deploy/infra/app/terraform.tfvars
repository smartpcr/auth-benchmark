# global
subscription_id="{{.Values.global.subscriptionId}}"
tenant_id="{{.Values.global.tenantId}}"
resource_group_name="{{.Values.global.resourceGroup.name}}"
location="{{.Values.global.resourceGroup.location}}"
vault_name="{{.Values.kv.name}}"

# app insights
app_insights_name="{{.Values.appInsights.name}}"

# function app
storage_account="{{.Values.storage.name}}"
artifact_container="{{.Values.storage.containers.artifacts.name}}"
function_app_name="{{.Values.apps.functionApp.name}}"