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
provision_storage_account="{{.Values.apps.storage.account}}"
artifact_container="{{.Values.storage.containers.artifacts.name}}"
telemetry_storage_account="{{.Values.storage.account}}"
events_container="{{.Values.storage.containers.events.name}}"
anomalies_container="{{.Values.storage.containers.anomalies.name}}"
alerts_container="{{.Values.storage.containers.alerts.name}}"

# cosmosdb
cosmosdb_account="{{.Values.cosmosdb.account}}"

# helloWorld function app
function_app_name="{{.Values.apps.helloWorld.name}}"
git_root_folder="{{.Values.apps.helloWorld.gitRootFolder}}"
app_relative_folder="{{.Values.apps.helloWorld.projectFolder}}"