function GetSettings() {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvName,
        [string]$SpaceName = ""
    )

    $gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
        $gitRootFolder = Split-Path $gitRootFolder -Parent
    }
    $deployFolder = Join-Path $gitRootFolder "deploy"
    $settingsFolder = Join-Path $deployFolder "settings"
    $settingYamlFile = Join-Path $settingsFolder "settings.yaml"
    if (-not (Test-Path $settingYamlFile)) {
        throw "Unable to find file '$settingYamlFile'"
    }
    $baseSettingContent = Get-Content $settingYamlFile -Raw
    $settings = $baseSettingContent | ConvertFrom-Yaml -Ordered

    # add imported files
    $settingNames = New-Object System.Collections.ArrayList
    $settings.Keys | ForEach-Object {
        $settingNames.Add($_) | Out-Null
    }
    $settingNames | ForEach-Object {
        $settingName = $_
        if ($null -ne $settings[$settingName]["importFromFile"]) {
            $file = Join-Path $settingsFolder $settings[$settingName]["importFromFile"]
            Write-Verbose "loading $settingName from $file"
            $fileContent = Get-Content $file -Raw
            $fileSettings = $fileContent | ConvertFrom-Yaml -Ordered
            $settings.Remove($settingName)
            if ($null -ne $fileSettings[$settingName]) {
                $settings[$settingName] = $fileSettings[$settingName]
            }
            else {
                $settings[$settingName] = $fileSettings
            }
        }
    }

    $envFolder = Join-Path $gitRootFolder $EnvName
    $envSettingFile = Join-Path $envFolder "settings.yaml"
    if (Test-Path $envSettingFile) {
        # load env settings
        $envValues = Get-Content $envSettingFile -Raw | ConvertFrom-Yaml -Ordered
        if ($null -ne $SpaceName -and $SpaceName -ne "") {
            $spaceValueFile = Join-Path (Join-Path $envFolder $SpaceName) "settings.yaml"
            if (Test-Path $spaceValueFile) {
                $spaceValues = Get-Content $spaceValueFile -Raw | ConvertFrom-Yaml -Ordered

                $envProps = GetProperties -subject $envValues
                $spaceProps = GetProperties -subject $spaceValues
                $spaceProps | ForEach-Object {
                    $propOverride = $_
                    $newValue = GetPropertyValue -subject $spaceValues -propertyPath $propOverride
                    $targetPropFound = $envProps | Where-Object { $_ -eq $propOverride }

                    if ($targetPropFound) {
                        $existingValue = GetPropertyValue -subject $envValues -propertyPath $targetPropFound
                        if ($null -ne $newValue -and $existingValue -ne $newValue) {
                            if (-not (Test-Path $settingYamlFile)) {
                                LogInfo -Message "Change property '$propOverride' value from '$existingValue' to '$newValue'..."
                            }
                            SetPropertyValue -targetObject $envValues -propertyPath $targetPropFound -propertyValue $newValue
                        }
                    }
                    else {
                        if (-not (Test-Path $settingYamlFile)) {
                            LogInfo -Message "Adding property '$propOverride' value '$newValue'..."
                        }
                        SetPropertyValue -targetObject $envValues -propertyPath $propOverride -propertyValue $newValue
                    }
                }
            }
        }

        $settingsYamlContent = $settings | ConvertTo-Yaml
        $settingsYamlContent = Set-YamlValues -ValueTemplate $settingsYamlContent -Settings $envValues
        $settings = $settingsYamlContent | ConvertFrom-Yaml -Ordered

        $envProps = GetProperties -subject $envValues
        $settingsProps = GetProperties -subject $settings
        $envProps | ForEach-Object {
            $propOverride = $_
            $newValue = GetPropertyValue -subject $envValues -propertyPath $propOverride
            $targetPropFound = $settingsProps | Where-Object { $_ -eq $propOverride }

            if ($targetPropFound) {
                $existingValue = GetPropertyValue -subject $settings -propertyPath $targetPropFound
                if ($null -ne $newValue -and $existingValue -ne $newValue) {
                    LogVerbose -Message "Change property '$propOverride' value from '$existingValue' to '$newValue'..."
                    SetPropertyValue -targetObject $settings -propertyPath $targetPropFound -propertyValue $newValue
                }
            }
            else {
                LogVerbose -Message "Adding property '$propOverride' value '$newValue'..."
                SetPropertyValue -targetObject $settings -propertyPath $propOverride -propertyValue $newValue
            }
        }
    }

    ResolveSelfReferencedFields -Settings $settings

    return $settings
}

function AddSvcSettings() {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvName,
        [object]$Settings
    )

    $gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
        $gitRootFolder = Split-Path $gitRootFolder -Parent
    }
    $settingsFolder = Join-Path $gitRootFolder "settings"
    $svcFolder = Join-Path $settingsFolder "svc"
    $aadAppYamlFile = Join-Path $svcFolder "aad_app.yaml"
    $aadApps = Get-Content $aadAppYamlFile -Raw | ConvertFrom-Yaml -Ordered
    $settings.svc["aadApps"] = $aadApps.services[$EnvName]
}

function GetEnvSslCerts() {
    param(
        [string]$EnvName
    )

    $settings = GetSettings -EnvName $EnvName

    $sslCerts = New-Object System.Collections.ArrayList
    LogInfo -Message "geneva-certificate"
    $sslCerts.Add(@{
            Name               = "Geneva-Certificate-Managed"
            KeyVaultCertName   = "Geneva-Certificate-Managed"
            KeyVaultSecretName = "Geneva-Certificate"
            KubeSecretName     = "geneva-certificate"
            KubeDataNameCrt    = "gcscert.pem"
            KubeDataNameKey    = "gcskey.pem"
        }) | Out-Null

    LogInfo -Message "ssl-aks-default-certificate"
    $sslCerts.Add(@{
            Name               = "Ssl-Aks-Default-Certificate-Managed"
            KeyVaultCertName   = "Ssl-Aks-Default-Certificate-Managed"
            KeyVaultSecretName = "Ssl-Aks-Default-Certificate"
            KubeSecretName     = "ssl-aks-default-certificate"
            KubeDataNameCrt    = "tls.crt"
            KubeDataNameKey    = "tls.key"
        }) | Out-Null

    LogInfo -Message "ssl-certificate"
    $sslCerts.Add(@{
            Name               = "Ssl-Certificate-Managed"
            KeyVaultCertName   = "Ssl-Certificate-Managed"
            KeyVaultSecretName = "Ssl-Certificate"
            KubeSecretName     = "ssl-certificate"
            KubeDataNameCrt    = "tls.crt"
            KubeDataNameKey    = "tls.key"
        }) | Out-Null

    LogInfo -Message "sslcert-default-svc-cluster-local"
    $sslCerts.Add(@{
            Name               = $settings.dns.internal.sslCert
            KeyVaultSecretName = $settings.dns.internal.vaultSecret
            KeyVaultCertName   = $settings.dns.internal.vaultCert
            KubeSecretName     = $settings.dns.internal.sslCert
            KubeDataNameCrt    = "tls.crt"
            KubeDataNameKey    = "tls.key"
        }) | Out-Null

    LogInfo -Message "$($settings.dns.sslCert)"
    $sslCerts.Add(@{
            Name               = $settings.dns.sslCert
            KeyVaultSecretName = $settings.dns.vaultSecret
            KeyVaultCertName   = $settings.dns.vaultCert
            KubeSecretName     = $settings.dns.sslCert
            KubeDataNameCrt    = "tls.crt"
            KubeDataNameKey    = "tls.key"
        }) | Out-Null

    return $sslCerts
}

function GetAadAccessObjectIds() {
    param(
        [array]$UserOrGroupNames
    )

    $userObjIds = New-Object System.Collections.ArrayList
    $groupObjIds = New-Object System.Collections.ArrayList

    if ($null -ne $UserOrGroupNames -and $UserOrGroupNames.Count -gt 0) {
        $UserOrGroupNames | ForEach-Object {
            if ($_.type -eq "user") {
                $username = $_.name
                $userFound = az ad user show --id $username | ConvertFrom-Json
                if ($null -ne $userFound) {
                    $userObjIds.Add($userFound.userPrincipalName) | Out-Null # NOTE: email, not objectid works for user role binding
                }
                else {
                    Write-Warning "No user found: '$username'"
                }
            }
            elseif ($_.type -eq "group") {
                $groupname = $_.name
                [array]$groupFound = az ad group show -g "$groupname" | ConvertFrom-Json
                if ($null -ne $groupFound) {
                    $groupObjIds.Add($groupFound.objectId) | Out-Null # for aad group, only objectid works
                }
                else {
                    Write-Warning "No group found: '$groupname'"
                }
            }
        }
    }

    return @{
        UserObjectIds  = $userObjIds
        GroupObjectIds = $groupObjIds
    }
}

function EnsureTerraformBackend() {
    param(
        [object]$Settings,
        [bool]$IsSharedResource
    )

    LogStep -Message "Ensure terraform resource group: '$($Settings.terraform.resourceGroup.name)'"
    [array]$tfRgs = az group list --query "[?name=='$($Settings.terraform.resourceGroup.name)']" | ConvertFrom-Json
    if ($null -eq $tfRgs -or $tfRgs.Count -eq 0) {
        $rg = az group create -n $Settings.terraform.resourceGroup.name --location $Settings.terraform.resourceGroup.location | ConvertFrom-Json
        LogStep -Message "Created resource group '$($rg.name)'"
    }
    else {
        $rg = $tfRgs[0]
    }

    LogStep -Message "Ensure backend storage account '$($Settings.terraform.backend.storageAccount)'"
    [array]$storageAccountsFound = az storage account list `
        --resource-group $Settings.terraform.resourceGroup.name `
        --query "[?name=='$($Settings.terraform.backend.storageAccount)']" | ConvertFrom-Json
    if ($null -eq $storageAccountsFound -or $storageAccountsFound.Count -eq 0) {
        $tfStorageAccount = az storage account create `
            --name $Settings.terraform.backend.storageAccount `
            --resource-group $Settings.terraform.resourceGroup.name `
            --location $Settings.terraform.resourceGroup.location `
            --sku Standard_LRS | ConvertFrom-Json
        LogInfo -Message "storage account '$($tfStorageAccount.name)' is created"
    }
    else {
        $tfStorageAccount = $storageAccountsFound[0]
    }

    LogStep -Message "Get storage key"
    $tfStorageKeys = az storage account keys list -g $Settings.terraform.resourceGroup.name -n $Settings.terraform.backend.storageAccount | ConvertFrom-Json
    $tfStorageKey = $tfStorageKeys[0].value

    LogStep -Message "Ensure blob container '$($Settings.terraform.backend.envContainerName)'"
    [array]$blobContainersFound = az storage container list `
        --account-name $tfStorageAccount.name `
        --account-key $tfStorageKey `
        --query "[?name=='$($Settings.terraform.backend.envContainerName)']" | ConvertFrom-Json
    if ($null -eq $blobContainersFound -or $blobContainersFound.Count -eq 0) {
        az storage container create --name $Settings.terraform.backend.envContainerName --account-name $tfStorageAccount.name --account-key $tfStorageKey | Out-Null
    }
    else {
        LogInfo -Message "blob container '$($Settings.terraform.backend.envContainerName)' already created"
    }

    LogStep -Message "Ensure blob container '$($Settings.terraform.backend.spaceContainerName)'"
    [array]$blobContainersFound = az storage container list `
        --account-name $tfStorageAccount.name `
        --account-key $tfStorageKey `
        --query "[?name=='$($Settings.terraform.backend.spaceContainerName)']" | ConvertFrom-Json
    if ($null -eq $blobContainersFound -or $blobContainersFound.Count -eq 0) {
        az storage container create --name $Settings.terraform.backend.spaceContainerName --account-name $tfStorageAccount.name --account-key $tfStorageKey | Out-Null
    }
    else {
        LogInfo -Message "blob container '$($Settings.terraform.backend.spaceContainerName)' already created"
    }

    $Settings.terraform.backend["accessKey"] = $tfStorageKey
    if ($IsSharedResource) {
        $Settings.terraform.backend["containerName"] = $Settings.terraform.backend.envContainerName
    }
    else {
        $Settings.terraform.backend["containerName"] = $Settings.terraform.backend.spaceContainerName
    }
    LogStep -Message "Using blob container '$($settings.terraform.backend.containerName)'"
}

function IsSharedResource() {
    param(
        [string]$EnvName,
        [string]$SpaceName,
        [string]$ResourceName
    )

    $envSettings = GetSettings -EnvName $EnvName
    $spaceSettings = GetSettings -EnvName $EnvName -SpaceName $SpaceName
    $sharedResourceSetting = $envSettings[$ResourceName]
    $nonSharedResourceSetting = $spaceSettings[$ResourceName]
    $isSettingTheSame = DeepEquals -Obj1 $sharedResourceSetting -Obj2 $nonSharedResourceSetting

    $isSharedResource = $true
    if ($isSettingTheSame -is [array] -or $isSettingTheSame.GetType().IsGenericType) {
        $isSettingTheSame | ForEach-Object {
            if ($_ -eq $false) {
                $isSharedResource = $false
            }
        }
    }
    else {
        $isSharedResource = $isSettingTheSame
    }

    return $isSharedResource
}

function GenerateTerraformManifest() {
    param(
        [string]$TerraformInputFolder,
        [string]$TerraformOutputFolder,
        [string]$ScriptFolder,
        [object]$Settings,
        [bool]$IsNullResource = $true
    )

    LogStep -Message "Generating terraform.tfvars"
    $tfVarFile = Join-Path $TerraformInputFolder "terraform.tfvars"
    $tfVarContent = Get-Content $tfVarFile -Raw
    $tfVarContent = Set-YamlValues -ValueTemplate $tfVarContent -Settings $Settings

    LogStep -Message "Generating backend.tfvars"
    $backendVarFle = Join-Path $TerraformInputFolder "backend.tfvars"
    $backendVarContent = Get-Content $backendVarFle -Raw
    $backendVarContent = Set-YamlValues -ValueTemplate $backendVarContent -Settings $Settings

    LogStep -Message "Clear terraform output folder: $TerraformOutputFolder"
    if (Test-Path $TerraformOutputFolder) {
        # keep terraform.tfstate, kubeconfig, otherwise it's going to re-create cluster or trying to connect to localhost
        $terraformTempFolder = Join-Path $TerraformOutputFolder ".terraform"
        if (Test-Path $terraformTempFolder) {
            Remove-Item $terraformTempFolder -Recurse -Force
        }
    }
    else {
        New-Item $TerraformOutputFolder -ItemType Directory -Force | Out-Null
    }

    LogStep -Message "Write terraform output to '$TerraformOutputFolder'"
    $tfVarContent | ToFile -File (Join-Path $TerraformOutputFolder "terraform.tfvars")
    $backendVarContent | ToFile -File (Join-Path $TerraformOutputFolder "backend.tfvars")
    Copy-Item (Join-Path $TerraformInputFolder "main.tf") -Destination (Join-Path $TerraformOutputFolder "main.tf") -Force
    Copy-Item (Join-Path $TerraformInputFolder "variables.tf") -Destination (Join-Path $TerraformOutputFolder "variables.tf") -Force
    $terraformInitFolder = Join-Path $TerraformOutputFolder ".terraform"
    if (Test-Path $terraformInitFolder) {
        Remove-Item $terraformInitFolder -Recurse -Force
    }

    LogStep -Message "populating script: RunTerraform.ps1"
    $Settings.terraform["backendFile"] = Join-Path $TerraformOutputFolder "backend.tfvars"
    $Settings.terraform["tfvarsFile"] = Join-Path $TerraformOutputFolder "terraform.tfvars"
    $Settings.terraform["tfPlanOutputFile"] = Join-Path $TerraformOutputFolder "tf_plan_out"
    $Settings.terraform["tfPlanLogFile"] = Join-Path $TerraformOutputFolder "tf_plan.log"

    # RunTerraform.ps1
    LogStep -Message "populating script file: RunTerraform.ps1"
    $terraformShellScriptFile = Join-Path $ScriptFolder "RunTerraform.ps1"
    $scriptContent = Get-Content $terraformShellScriptFile -Raw
    $Settings["isNullResource"] = if ($IsNullResource) { "true" } else { "false" }
    $scriptContent = Set-YamlValues -ValueTemplate $scriptContent -Settings $Settings
    $terraformShellFile = Join-Path $TerraformOutputFolder "RunTerraform.ps1"
    $scriptContent | ToFile -File $terraformShellFile
    Invoke-Expression "chmod +x `"$terraformShellFile`""

    LogStep -Message "populating script file: ApplyTerraform.ps1"
    $applyTerraformShellScriptFile = Join-Path $ScriptFolder "ApplyTerraform.ps1"
    $applyTerraformScriptContent = Get-Content $applyTerraformShellScriptFile -Raw
    $applyTerraformScriptContent = Set-YamlValues -ValueTemplate $applyTerraformScriptContent -Settings $Settings
    $applyTerraformShellFile = Join-Path $TerraformOutputFolder "ApplyTerraform.ps1"
    $applyTerraformScriptContent | ToFile -File $applyTerraformShellFile
}

function CopyFiles() {
    param(
        [string]$SourceFolder,
        [string]$TargetFolder,
        [string[]]$Files
    )

    $Files | ForEach-Object {
        $fileName = $_
        $sourceFilePath = Join-Path $SourceFolder $fileName
        $targetFilePath = Join-Path $TargetFolder $fileName
        if (-not (Test-Path $sourceFilePath)) {
            throw "Unable to find file: $sourceFilePath"
        }
        if (Test-Path $targetFilePath) {
            Remove-Item $targetFilePath
        }
        $destinationFolder = Split-Path -Path $targetFilePath -Parent
        if (-not (Test-Path $destinationFolder)) {
            New-Item $destinationFolder -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $sourceFilePath -Destination $targetFilePath -Force
    }
}

function GetPropertyValues() {
    param(
        [object]$Subject
    )

    $propValues = New-Object System.Collections.ArrayList
    $props = GetProperties -subject $Subject
    $props | ForEach-Object {
        $propPath = $_
        $propValue = GetPropertyValue -subject $Subject -propertyPath $propPath

        $propValues.Add(@{
                Name  = $propPath
                Value = $propValue
            }) | Out-Null
    }

    return $propValues
}

function DeepEquals() {
    param(
        [object]$Obj1,
        [object]$Obj2
    )

    if (IsPrimitiveValue -inputValue $Obj1) {
        return $Obj1 -eq $Obj2
    }

    if ($Obj1 -is [array] -or $Obj1.GetType().IsGenericType) {
        $idx = 0
        while ($idx -lt $Obj1.Count) {
            $val1 = $Obj1[$idx]
            $val2 = $Obj2[$idx]
            if (-not (DeepEquals -Obj1 $val1 -Obj2 $val2)) {
                return $false
            }
            $idx++
        }

        return $true
    }

    $propVals1 = GetPropertyValues -Subject $Obj1
    $propVals2 = GetPropertyValues -Subject $Obj2
    if ($propVals1.Count -ne $propVals2.Count) {
        return $false
    }

    $propVals1 | ForEach-Object {
        $prop = $_
        $propName = $prop.Name
        $value1 = $prop.Value
        $prop2 = $propVals2 | Where-Object { $_.Name -eq $propName }
        $value2 = if ($null -eq $prop2) { $null } else { $prop2.Value }
        if ($value1.GetType() -ne $value2.GetType()) {
            return $false
        }
        if ($value1 -is [array] -or $value1.GetType().IsGenericType) {
            $idx = 0
            while ($idx -lt $value1.Count) {
                $val1 = $value1[$idx]
                $val2 = $value2[$idx]
                if (-not (DeepEquals -Obj1 $val1 -Obj2 $val2)) {
                    return $false
                }
                $idx++
            }
        }
        else {
            if (-not (DeepEquals -Obj1 $value1 -Obj2 $value2)) {
                return $false
            }
        }
    }
    return $true
}