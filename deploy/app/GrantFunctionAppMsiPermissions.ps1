param(
    [Parameter(Position = 0, mandatory = $true)]
    [string]$AppName,

    [Parameter(Position = 1, mandatory = $true)]
    [ValidateScript( { Test-Path $_ })]
    [string]$GitRootFolder,

    [Parameter(Position = 2, mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Position = 3, mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Position = 4, mandatory = $true)]
    [string]$StorageAccountName,

    [string[]]$Containers
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$deployFolder = Join-Path $gitRootFolder "deploy"
$scriptFolder = Join-Path $deployFolder "scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "Common.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Grant permission to app identity (MSI)"

UsingScope("picking function app MSI") {
    $functionApp = az functionapp show -n $AppName -g $ResourceGroupName | ConvertFrom-Json
    $systemAssignedIdentity = @{
        principalId = $functionApp.identity.principalId
        tenantId    = $functionApp.identity.tenantId
    }
    if ($null -eq $systemAssignedIdentity.principalId) {
        throw "Identity/SystemAssignedIdentity is not turned on"
    }
    LogInfo -Message "MSI principal id: $($systemAssignedIdentity.principalId)"
}

UsingScope("ensure access to storage account") {
    $storageAccount = az storage account show -n $StorageAccountName | ConvertFrom-Json
    $roleName = "Storage Blob Data Contributor"
    if ($null -eq $Containers -or $Containers.Count -eq 0) {
        LogInfo -Message "ensuring assignment for role '$roleName' and storage account '$StorageAccountName'"
        [array]$existingAssignments = az role assignment list `
            --role $roleName `
            --assignee $systemAssignedIdentity.principalId `
            --scope $storageAccount.id | ConvertFrom-Json
        if ($null -eq $existingAssignments -or $existingAssignments.Count -eq 0) {
            LogStep -Message "granting '$roleName' access to storage account '$StorageAccountName'"
            az role assignment create `
                --assignee $systemAssignedIdentity.principalId `
                --role $roleName `
                --scope $storageAccount.id | Out-Null
        }
        else {
            LogInfo -Message "role assignment already exists"
        }
    }
    else {
        $Containers | ForEach-Object {
            $containerName = $_
            LogStep -Message "ensuring assignment for role '$roleName' and container '$containerName'"
            $containerScope = "$($storageAccount.id)/blobServices/default/containers/$($containerName)"
            [array]$existingAssignments = az role assignment list `
                --role $roleName `
                --assignee $systemAssignedIdentity.principalId `
                --scope $containerScope | ConvertFrom-Json
            if ($null -eq $existingAssignments -or $existingAssignments.Count -eq 0) {
                LogInfo -Message "granting '$roleName' access to storage container: '$containerName'"
                az role assignment create `
                    --assignee $systemAssignedIdentity.principalId `
                    --role $roleName `
                    --scope $containerScope | Out-Null
            }
            else {
                LogInfo -Message "role assignment already exists"
            }
        }
    }
}
