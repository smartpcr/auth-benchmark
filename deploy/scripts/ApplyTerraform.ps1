$env:ARM_SUBSCRIPTION_ID="{{.Values.global.subscriptionId}}"
$env:ARM_TENANT_ID="{{.Values.global.tenantId}}"
$env:ARM_CLIENT_ID="{{.Values.terraform.spn.appId}}"
$env:ARM_CLIENT_SECRET="{{.Values.terraform.spn.pwd}}"

terraform apply ./tf_plan_out