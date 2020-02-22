
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

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Publish App"

UsingScope("retrieving settings") {
    $settings = GetSettings -EnvName $EnvName -SpaceName $SpaceName
    LogStep -Message "Settings retrieved for '$($settings.global.subscriptionName)/$($EnvName)-$($SpaceName)'"
}

UsingScope("login") {
    $azAccount = Login -SubscriptionName $settings.global.subscriptionName -TenantId $settings.global.tenantId
    $settings.global["subscriptionId"] = $azAccount.id
    $settings.global["tenantId"] = $azAccount.tenantId
    LogStep -Message "Logged in as user '$($azAccount.user.type)/$($azAccount.user.name)'"
}

UsingScope("retrieve app settings") {
    $appFolder = Join-Path $gitRootFolder $settings.apps.functionApp.projectFolder
    if (-not (Test-Path $appFolder)) {
        throw "Unable to find app folder: '$appFolder'"
    }
    Set-Location $appFolder

    LogStep -Message "publish function app..."
    func azure functionapp publish $settings.apps.functionApp.name
}

UsingScope("done") {
    LogInfo -Message "Finished!"
}
