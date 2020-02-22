# global
subscription_id="{{.Values.global.subscriptionId}}"
tenant_id="{{.Values.global.tenantId}}"
env_name="{{.Values.global.envName}}"
space_name="{{.Values.global.spaceName}}"
resource_group_name="{{.Values.global.resourceGroup.name}}"
location="{{.Values.global.resourceGroup.location}}"
vault_name="{{.Values.kv.name}}"

# app insights
app_insights_name="{{.Values.appInsights.name}}"

# msi
app_identity_name="{{.Values.userIdentity.writer.name}}"

# storage
storage_account="{{.Values.storage.name}}"
artifact_container="{{.Values.storage.containers.artifacts.name}}"
events_container="{{.Values.storage.containers.events.name}}"
anomaliess_container="{{.Values.storage.containers.anomalies.name}}"
alerts_container="{{.Values.storage.containers.alerts.name}}"

# function app
function_app_name="{{.Values.apps.functionApp.name}}"