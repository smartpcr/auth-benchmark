
param(
    [string]$GitRootFolder,
    [object]$AppRelativeFolder
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

$appFolder = Join-Path $GitRootFolder $AppRelativeFolder
if (-not (Test-Path $appFolder)) {
    throw "Unable to find app folder '$appFolder'"
}

UsingScope("publish app") {
    Set-Location $appFolder
    LogStep -Message "publish function app..."
    func azure functionapp publish $settings.apps.functionApp.name
    
    Set-Location $GitRootFolder
    LogStep -Message "Done!"
}