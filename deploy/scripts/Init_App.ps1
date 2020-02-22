
param(
    [string]$EnvName = "dev",
    [string]$SpaceName = "xd"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$deployFolder = Join-Path $gitRootFolder "deploy"
$scriptFolder = Join-Path $deployFolder "scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "Common.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $moduleFolder "Settings.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force

$appInfraFolder = Join-Path $deployFolder "app"
$tempFolder = Join-Path $scriptFolder "temp"
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}
$tempFolder = Join-Path $tempFolder $EnvName
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}
$terraformOutputFolder = Join-Path $tempFolder "app"
if (-not (Test-Path $terraformOutputFolder)) {
    New-Item $terraformOutputFolder -ItemType Directory -Force | Out-Null
}

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-App"

UsingScope("retrieving settings") {
    $settings = GetSettings -EnvName $EnvName -SpaceName $SpaceName
    LogStep -Message "Settings retrieved for '$($settings.global.subscriptionName)/$($EnvName)-$($SpaceName)'"
}

UsingScope("login") {
    $azAccount = Login -SubscriptionName $settings.global.subscriptionName -TenantId $settings.global.tenantId
    $settings.global["subscriptionId"] = $azAccount.id
    $settings.global["tenantId"] = $azAccount.tenantId
    LogStep -Message "Logged in as user '$($azAccount.user.type)/$($azAccount.user.name)'"

    $allSubscriptions = az account list | ConvertFrom-Json
    LogStep -Message "Total of $($allSubscriptions.Count) subscriptions available"
}

UsingScope("Ensure user identities") {
    if ($null -ne $settings.userIdentity.reader) {
        [array]$identitiesFound = az identity list -g $settings.userIdentity.reader.resourceGroup.name --query "[?name=='$($settings.userIdentity.reader.name)']" | ConvertFrom-Json
        if ($null -eq $identitiesFound -or $identitiesFound.Count -eq 0) {
            az identity create -g $settings.userIdentity.reader.resourceGroup.name -n $settings.userIdentity.reader.name | Out-Null
            LogStep -Message "user identity '$($settings.userIdentity.reader.name)' is created in group '$($settings.userIdentity.reader.resourceGroup.name)'"
        }
    }

    if ($null -ne $settings.userIdentity.writer) {
        [array]$identitiesFound = az identity list -g $settings.userIdentity.writer.resourceGroup.name --query "[?name=='$($settings.userIdentity.writer.name)']" | ConvertFrom-Json
        if ($null -eq $identitiesFound -or $identitiesFound.Count -eq 0) {
            az identity create -g $settings.userIdentity.writer.resourceGroup.name -n $settings.userIdentity.writer.name | Out-Null
            LogStep -Message "user identity '$($settings.userIdentity.writer.name)' is created in group '$($settings.userIdentity.writer.resourceGroup.name)'"
        }
    }
}

UsingScope("Ensure app resource group") {
    [array]$appRgs = az group list --query "[?name=='$($settings.apps.functionApp.resourceGroup.name)']" | ConvertFrom-Json
    if ($null -eq $appRgs -or $appRgs.Count -eq 0) {
        $rg = az group create -n $settings.apps.functionApp.resourceGroup.name --location $settings.apps.functionApp.resourceGroup.location | ConvertFrom-Json
        LogStep -Message "Created resource group '$($rg.name)'"
    }
    else {
        $rg = $appRgs[0]
    }
}

UsingScope("Ensure keyvault") {
    LogStep -Message "Ensure vault '$($settings.kv.name)' is created in '$($settings.kv.resourceGroup.name)'"
    [array]$existingKvs = az keyvault list --resource-group $settings.kv.resourceGroup.name --query "[?name=='$($settings.kv.name)']" | ConvertFrom-Json
    if ($null -eq $existingKvs -or $existingKvs.Count -eq 0) {
        $kv = az keyvault create `
            --resource-group $settings.kv.resourceGroup.name `
            --name $settings.kv.name `
            --sku standard `
            --location $settings.kv.resourceGroup.location `
            --enabled-for-deployment $true `
            --enabled-for-disk-encryption $true `
            --enabled-for-template-deployment $true | ConvertFrom-Json
        LogStep -Message "Created key vault '$($kv.name)'"
    }
    else {
        $kv = $existingKvs[0]
    }

    LogStep -Message "Ensure approprivate access policy for kv"
    if ($null -ne $settings.kv.readers) {
        [array]$settings.kv.readers | ForEach-Object {
            $readerName = $_
            LogInfo -Message "ensure reader access policy assigned to '$readerName'"
            [array]$aadObjsFound = az ad sp list --display-name $readerName | ConvertFrom-Json
            if ($null -eq $aadObjsFound -or $aadObjsFound.Count -eq 0) {
                throw "aad object with name '$readerName' is not created"
            }
            if ($aadObjsFound.Count -gt 1) {
                throw "more than one aad objects with name '$readerName' found"
            }
            az keyvault set-policy `
                --name $settings.kv.name `
                --object-id $aadObjsFound[0].objectId `
                --spn $aadObjsFound[0].displayName `
                --certificate-permissions get list `
                --secret-permissions get list | Out-Null
        }
    }

    if ($null -ne $settings.kv.writers) {
        [array]$settings.kv.writers | ForEach-Object {
            $writerName = $_
            LogInfo -Message "ensure writer access policy assigned to '$writerName'"
            [array]$aadObjsFound = az ad sp list --display-name $writerName | ConvertFrom-Json
            if ($null -eq $aadObjsFound -or $aadObjsFound.Count -eq 0) {
                throw "aad object with name '$writerName' is not created"
            }
            if ($aadObjsFound.Count -gt 1) {
                throw "more than one aad objects with name '$writerName' found"
            }
            az keyvault set-policy `
                -n $settings.kv.name `
                --secret-permissions backup delete get list purge recover restore set `
                --object-id $aadObjsFound[0].objectId | Out-Null
            az keyvault set-policy `
                -n $settings.kv.name `
                --storage-permissions backup delete deletesas get getsas list listsas purge recover regeneratekey restore set setsas update `
                --object-id $aadObjsFound[0].objectId | Out-Null
        }
    }
}

UsingScope("Ensure terraform spn") {
    $tfSpnObjSecret = TryGetSecret -VaultName $settings.kv.name -SecretName "tf-spn-obj"
    $tfSpnObj = $tfSpnObjSecret.value | FromBase64 | ConvertFrom-Json
    $settings.terraform["spn"] = @{
        appId         = $tfSpnObj.appId
        pwd           = $tfSpnObj.pwd
        objectId      = $tfSpnObj.objId
        clientAppName = $tfSpnObj.name
    }

    LogInfo -Message "Ensure terraform spn have access to kv"
    az keyvault set-policy `
        -n $settings.kv.name `
        --secret-permissions backup delete get list purge recover restore set `
        --object-id $tfSpnObj.objId | Out-Null
    az keyvault set-policy `
        -n $settings.kv.name `
        --storage-permissions backup delete deletesas get getsas list listsas purge recover regeneratekey restore set setsas update `
        --object-id $tfSpnObj.objId | Out-Null
}

UsingScope("Ensure terraform backend") {
    EnsureTerraformBackend -Settings $settings -IsSharedResource $false
}

UsingScope("Populate function app settings") {
    $settings.apps.functionApp["gitRootFolder"] = $gitRootFolder
}

UsingScope("Setup terraform variables") {
    GenerateTerraformManifest `
        -TerraformInputFolder $appInfraFolder `
        -TerraformOutputFolder $terraformOutputFolder `
        -ScriptFolder $scriptFolder `
        -Settings $settings

    $additionalFiles = @(
        "PublishFunctionApp.ps1"
    )
    CopyFiles -SourceFolder $appInfraFolder -TargetFolder $terraformOutputFolder -Files $additionalFiles
}

UsingScope("Done") {
    Set-Location $gitRootFolder
}
