
$env:ARM_SUBSCRIPTION_ID="{{.Values.global.subscriptionId}}"
$env:ARM_TENANT_ID="{{.Values.global.tenantId}}"
$env:ARM_CLIENT_ID="{{.Values.terraform.spn.appId}}"
$env:ARM_CLIENT_SECRET="{{.Values.terraform.spn.pwd}}"
$IS_NULL_RESOURCE="{{.Values.isNullResource}}"

Write-Host "terraform init -backend-config=`"{{.Values.terraform.backendFile}}`""
terraform init -backend-config="{{.Values.terraform.backendFile}}"

if ($env:IS_NULL_RESOURCE -eq "false") {
    Write-Host "terraform refresh"
    terraform refresh
}

Write-Host "terraform plan -var-file=`"{{.Values.terraform.tfvarsFile}}`"  -out `"{{.Values.terraform.tfPlanOutputFile}}`" | tee `"{{.Values.terraform.tfPlanLogFile}}`""
terraform plan -var-file="{{.Values.terraform.tfvarsFile}}" -out "{{.Values.terraform.tfPlanOutputFile}}" | Out-File "{{.Values.terraform.tfPlanLogFile}}"
Get-Content "{{.Values.terraform.tfPlanLogFile}}" | Write-Host