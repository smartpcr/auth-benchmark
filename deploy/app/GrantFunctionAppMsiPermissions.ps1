param(
    [string]$AppName = "helloworld-dev-xd-func-app",
    [string]$ResourceGroupName = "functions-rg",
    [string]$SubscriptionId = "c5a015e6-a59b-45bd-a621-82f447f46034",
    [string]$StorageAccountName = "functionsstoredev",
    [string[]]$Containers = @("events", "anomalies", "alerts")
)

$functionApp = az functionapp show -n $AppName -g $ResourceGroupName | ConvertFrom-Json
$systemAssignedIdentity = @{
    principalId = $functionApp.identity.principalId
    tenantId    = $functionApp.identity.tenantId
}
if ($null -eq $systemAssignedIdentity.principalId) {
    throw "Identity/SystemAssignedIdentity is not turned on"
}

$storageAccount = az storage account show -n $StorageAccountName | ConvertFrom-Json
$roleName = "Storage Blob Data Contributor"
if ($null -eq $Containers -or $Containers.Count -eq 0) {
    Write-Host "ensuring assignment for role '$roleName'"
    [array]$existingAssignments = az role assignment list `
        --role $roleName `
        --assignee $systemAssignedIdentity.principalId `
        --scope $storageAccount.id | ConvertFrom-Json
    if ($null -eq $existingAssignments -or $existingAssignments.Count -eq 0) {
        Write-Host "granting '$roleName' access to storage account '$StorageAccountName'"
        az role assignment create `
            --assignee $systemAssignedIdentity.principalId `
            --role $roleName `
            --scope $storageAccount.id | Out-Null
    }
    else {
        Write-Host "role assignment already exists"
    }
}
else {
    $Containers | ForEach-Object {
        $containerName = $_
        Write-Host "ensuring assignment for role '$roleName'"
        $containerScope = "$($storageAccount.id)/blobServices/default/containers/$($containerName)"
        [array]$existingAssignments = az role assignment list `
            --role $roleName `
            --assignee $systemAssignedIdentity.principalId `
            --scope $containerScope | ConvertFrom-Json
        if ($null -eq $existingAssignments -or $existingAssignments.Count -eq 0) {
            Write-Host "granting '$roleName' access to storage container: '$containerName'"
            az role assignment create `
                --assignee $systemAssignedIdentity.principalId `
                --role $roleName `
                --scope $containerScope | Out-Null
        }
        else {
            Write-Host "role assignment already exists"
        }
    }
}
