function Get-OrCreatePasswordInVault {
    param(
        [string] $VaultName,
        [string] $SecretName
    )

    $idQuery = "https://$($VaultName).vault.azure.net/secrets/$($SecretName)"
    [array]$secretsFound = az keyvault secret list `
        --vault-name $VaultName `
        --query "[?starts_with(id, '$idQuery')]" | ConvertFrom-Json

    $secretIsFound = $false
    if ($null -eq $secretsFound -or $secretsFound.Count -eq 0) {
        $secretsFound = $false
    }
    else {
        $secretIsFound = $true
    }

    if (!$secretIsFound) {
        LogInfo -Message "creating new secret '$SecretName'"
        $password = [System.Guid]::NewGuid().ToString()
        az keyvault secret set --vault-name $VaultName --name $SecretName --value $password | Out-Null
        $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
        return $res
    }

    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    if ($res) {
        return $res
    }
}

function EnsureCertificateInKeyVault {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $ScriptFolder
    )

    $existingCert = az keyvault certificate list --vault-name $VaultName --query "[?id=='https://$VaultName.vault.azure.net/certificates/$CertName']" | ConvertFrom-Json
    if ($existingCert) {
        LogInfo -Message "Certificate '$CertName' already exists in vault '$VaultName'"
    }
    else {
        $credentialFolder = Join-Path $ScriptFolder "credential"
        New-Item -Path $credentialFolder -ItemType Directory -Force | Out-Null
        $defaultPolicyFile = Join-Path $credentialFolder "default_policy.json"
        $defaultPolicyJson = "$(az keyvault certificate get-default-policy)"
        $defaultPolicyJson | ToFile -File $defaultPolicyFile
        az keyvault certificate create -n $CertName --vault-name $vaultName -p @$defaultPolicyFile | Out-Null
    }
}

function DownloadCertFromKeyVault {
    param(
        [string]$VaultName,
        [string]$CertName,
        [string]$ScriptFolder
    )

    $credentialFolder = Join-Path $ScriptFolder "credential"
    if (-not (Test-Path $credentialFolder)) {
        New-Item $credentialFolder -ItemType Directory -Force | Out-Null
    }
    $pfxCertFile = Join-Path $credentialFolder "$CertName.pfx"
    $pemCertFile = Join-Path $credentialFolder "$CertName.pem"
    $keyCertFile = Join-Path $credentialFolder "$CertName.key"
    if (Test-Path $pfxCertFile) {
        Remove-Item $pfxCertFile
    }
    if (Test-Path $pemCertFile) {
        Remove-Item $pemCertFile
    }
    if (Test-Path $keyCertFile) {
        Remove-Item $keyCertFile
    }
    az keyvault secret download --vault-name $settings.kv.name -n $CertName -e base64 -f $pfxCertFile
    openssl pkcs12 -in $pfxCertFile -clcerts -nodes -out $keyCertFile -passin pass:
    openssl rsa -in $keyCertFile -out $pemCertFile
}

function ImportCertFromMasterKeyVault {
    param(
        [string]$CertName,
        [string]$VaultName,
        [string]$MasterVaultName,
        [string]$TempFolder
    )

    $certFile = Join-Path $TempFolder "$CertName.pfx"
    if (Test-Path $certFile) {
        Remove-Item $certFile -Force | Out-Null
    }
    if ($CertName.EndsWith("-Managed")) {
        az keyvault secret download --vault-name $MasterVaultName --name $CertName -e base64 -f $certFile
    }
    else {
        az keyvault certificate download --file $certFile --name $CertName --encoding PEM --vault-name $MasterVaultName
    }

    $certAlreadyExist = IsCertExists -VaultName $VaultName -CertName $CertName
    if ($certAlreadyExist -eq $true) {
        az keyvault certificate delete --vault-name $VaultName --name $CertName | Out-Null
    }
    $certSecretExist = IsSecretExists -VaultName $VaultName -SecretName $CertName
    if ($certSecretExist -eq $true) {
        az keyvault secret delete --vault-name $VaultName --name $CertName | Out-Null
    }
    az keyvault certificate import --file $certFile --name $CertName --vault-name $VaultName | Out-Null
}

function TryGetSecret() {
    param(
        [string]$VaultName,
        [string]$SecretName
    )

    $idQuery = "https://$($VaultName).vault.azure.net/secrets/$($SecretName)"
    [array]$secretsFound = az keyvault secret list `
        --vault-name $VaultName `
        --query "[?starts_with(id, '$idQuery')]" | ConvertFrom-Json
    $secretIsFound = $false
    if ($null -eq $secretsFound -or $secretsFound.Count -eq 0) {
        $secretsFound = $false
    }
    else {
        $secretIsFound = $true
    }

    if ($secretIsFound) {
        $secret = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
        return $secret
    }

    return $null
}

function TryDownloadCert() {
    param(
        [string]$VaultName,
        [string]$CertName,
        [string]$TempFolder
    )

    $certExists = IsCertExists -VaultName $VaultName -CertName $CertName
    if ($certExists) {
        $certFile = Join-Path $TempFolder $CertName
        if (Test-Path $certFile) {
            Remove-Item $certFile -Force
        }
        if ($CertName.EndsWith("-Managed")) {
            az keyvault secret download --vault-name $VaultName --name $certName -e base64 -f $certFile
        }
        else {
            az keyvault certificate download --vault-name $VaultName --name $certName --encoding PEM --file $certFile
        }
        return $certFile
    }

    return $null
}
function TryGetSpnObjWithoutSuffix() {
    param(
        [string]$VaultName,
        [string]$SecretNameWithoutSuffix,
        [string]$AppId
    )

    $secretIds = az keyvault secret list --vault-name $VaultName --query "[?contains(id, '$SecretNameWithoutSuffix')]" | ConvertFrom-Json
    $spnFound = $null
    $secretIds | ForEach-Object {
        [string]$secretId = $_.id
        $secretName = $secretId.SubString($secretId.LastIndexOf("/") + 1)
        if ($null -eq $spnFound) {
            $secret = az keyvault secret show --vault-name $VaultName --name $secretName | ConvertFrom-Json
            $spnObj = $secret.value | FromBase64 | ConvertFrom-Json
            if ($spnObj.appId -ieq $AppId) {
                $spnFound = $spnObj
            }
        }
    }
    return $spnFound
}

function GetSecretWithFallback() {
    param(
        [string]$SecretName,
        [string]$MyVaultName,
        [string]$MySubscriptionName,
        [string]$MasterVaultName,
        [string]$MasterVaultSubscriptionName,
        [switch]$NoSuffix,
        [string]$TenantId
    )

    $BackupSecretName = $SecretName
    if (!$NoSuffix) {
        $suffix = GetHash $MyVaultName
        $BackupSecretName = $SecretName + "-" + $suffix
    }
    Login -SubscriptionName $MySubscriptionName -TenantId $TenantId | Out-Null
    $secret = TryGetSecret -VaultName $MyVaultName -SecretName $SecretName

    if ($null -eq $secret) {
        LogInfo -Message "fall back to secret '$BackupSecretName' in vault '$MasterVaultName'"
        Login -SubscriptionName $MasterVaultSubscriptionName -TenantId $TenantId | Out-Null
        $backupSecret = TryGetSecret -VaultName $MasterVaultName -SecretName $BackupSecretName
        if ($null -ne $backupSecret) {
            $tempFile = [System.IO.Path]::GetTempFileName()
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }

            Login -SubscriptionName $MasterVaultSubscriptionName -TenantId $TenantId | Out-Null
            az keyvault secret download --vault-name $MasterVaultName --name $BackupSecretName --file $tempFile

            Login -SubscriptionName $MySubscriptionName -TenantId $TenantId | Out-Null
            az keyvault secret set --vault-name $MyVaultName --name $SecretName --file $tempFile | Out-Null
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
            $secret = TryGetSecret -VaultName $MyVaultName -SecretName $SecretName
        }
        else {
            throw "Secret '$SecretName' not found in '$MyVaultName' or '$MasterVaultName'"
        }
    }
    else {
        Login -SubscriptionName $MasterVaultSubscriptionName -TenantId $TenantId | Out-Null
        $backupSecret = TryGetSecret -VaultName $MasterVaultName -SecretName $BackupSecretName
        if ($null -eq $backupSecret) {
            LogInfo -Message "back fill secret to master vault: $SecretName"
            $tempFile = [System.IO.Path]::GetTempFileName()
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
            Login -SubscriptionName $MySubscriptionName -TenantId $TenantId | Out-Null
            az keyvault secret download --vault-name $MyVaultName --name $SecretName --file $tempFile

            Login -SubscriptionName $MasterVaultSubscriptionName -TenantId $TenantId | Out-Null
            az keyvault secret set --vault-name $MasterVaultName --name $BackupSecretName --file $tempFile | Out-Null
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }
        elseif ($backupSecret.value -ne $secret.value) {
            LogInfo -Message "Update '$SecretName' from '$MasterVaultName'"
            Login -SubscriptionName $MySubscriptionName -TenantId $TenantId | Out-Null
            TrySetSecret -VaultName $MyVaultName -Name $SecretName -Value $backupSecret.value | Out-Null
            $secret = TryGetSecret -VaultName $MyVaultName -SecretName $SecretName
        }
        else {
            LogInfo -Message "Secret '$SecretName' not changed"
        }
    }

    return $secret
}

function IsCertExists() {
    param(
        [string]$VaultName,
        [string]$CertName
    )

    $certificateId = "https://$($VaultName).vault.azure.net/certificates/$($CertName)"
    [array]$existingCerts = az keyvault certificate list --vault-name $VaultName --query "[?id=='$($certificateId)']" | ConvertFrom-Json
    return $null -ne $existingCerts -and $existingCerts.Count -gt 0
}

function IsSecretExists() {
    param(
        [string]$VaultName,
        [string]$SecretName
    )

    $secretId = "https://$($VaultName).vault.azure.net/secrets/$($SecretName)"
    [array]$existingSecrets = az keyvault secret list --vault-name $VaultName --query "[?id=='$($secretId)']" | ConvertFrom-Json
    return $null -ne $existingSecrets -and $existingSecrets.Count -gt 0
}

function TrySetSecret() {
    param(
        [string]$VaultName,
        [string]$Name,
        [string]$Value
    )

    $tempFile = [System.IO.Path]::GetTempFileName()
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
    $Value | ToFile -File $tempFile

    $isSecretExist = IsSecretExists -VaultName $VaultName -SecretName $Name
    if (!$isSecretExist) {
        LogInfo -Message "secret '$Name' is created"
        $secret = az keyvault secret set --vault-name $VaultName --name $Name --file $tempFile | ConvertFrom-Json
    }
    else {
        $secret = az keyvault secret show --vault-name $VaultName --name $Name | ConvertFrom-Json
        if ($secret.value -ne $Value) {
            LogInfo -Message "secret '$Name' is updated"
            $secret = az keyvault secret set --vault-name $VaultName --name $Name --file $tempFile | ConvertFrom-Json
        }
        else {
            LogInfo -Message "secret '$Name' is not changed"
        }
    }

    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }

    [string]$id = $secret.id
    return $id.SubString($id.LastIndexOf("/") + 1)
}

function CopySecret() {
    param(
        [string]$FromVault,
        [string]$FromSecret,
        [string]$ToVault,
        [string]$ToSecret
    )

    $tempFile = [System.IO.Path]::GetTempFileName()
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
    az keyvault secret download --vault-name $FromVault --name $FromSecret --file $tempFile
    $newSecret = az keyvault secret set --vault-name $ToVault --name $ToSecret --file $tempFile | ConvertFrom-Json
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
    [string]$id = $newSecret.id
    return $id.SubString($id.LastIndexOf("/") + 1)
}

function TrySetSecretFromFile() {
    param(
        [string]$VaultName,
        [string]$Name,
        [string]$File
    )

    $isSecretExist = IsSecretExists -VaultName $VaultName -SecretName $Name
    if (!$isSecretExist) {
        $secret = az keyvault secret set --vault-name $VaultName --name $Name --file $File | ConvertFrom-Json
    }
    else {
        $secret = az keyvault secret show --vault-name $VaultName --name $Name | ConvertFrom-Json
        if ($secret.value -ne $Value) {
            $secret = az keyvault secret set --vault-name $VaultName --name $Name --file $File | ConvertFrom-Json
        }
    }

    [string]$id = $secret.id
    return $id.SubString($id.LastIndexOf("/") + 1)
}

function TrySetCert() {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $CertFile,
        [string] $Thumbprint
    )

    $certFound = IsCertExists -VaultName $VaultName -CertName $CertName
    if (!$certFound) {
        LogInfo -Message "new cert, creating"
        # $certAlreadyExist = IsCertExists -VaultName $TgtVaultName -CertName $name
        # if ($certAlreadyExist -eq $true) {
        #     az keyvault certificate delete --vault-name $TgtVaultName --name $name | Out-Null
        # }
        $certSecretExist = IsSecretExists -VaultName $TgtVaultName -SecretName $name
        if ($certSecretExist -eq $true) {
            LogInfo -Message "adding cert, removing associated secret: $name"
            az keyvault secret delete --vault-name $TgtVaultName --name $name | Out-Null
        }

        $cert = az keyvault certificate import --vault-name $VaultName --name $CertName --file $CertFile
    }
    else {
        $existingCert = az keyvault certificate show --vault-name $VaultName --name $CertName | ConvertFrom-Json
        if ($existingCert.x509ThumbprintHex -ne $Thumbprint) {
            $certSecretExist = IsSecretExists -VaultName $TgtVaultName -SecretName $name
            if ($certSecretExist -eq $true) {
                LogInfo -Message "updating cert, removing associated secret: $name"
                az keyvault secret delete --vault-name $TgtVaultName --name $name | Out-Null
            }
            LogInfo -Message "cert changed, updating"
            $cert = az keyvault certificate import --vault-name $VaultName --name $CertName --file $CertFile
        }
        else {
            LogInfo -Message "cert not changed"
            $cert = $existingCert
        }
    }

    return $cert
}
function Initialize-BouncyCastleSupport {
    $tempPath = $env:TEMP
    if ($null -eq $tempPath) {
        $tempPath = "/tmp"
    }

    $bouncyCastleDllPath = Join-Path $tempPath "BouncyCastle.Crypto.dll"

    if (-not (Test-Path $bouncyCastleDllPath)) {
        Invoke-WebRequest `
            -Uri "https://avalanchebuildsupport.blob.core.windows.net/files/BouncyCastle.Crypto.dll" `
            -OutFile $bouncyCastleDllPath
    }

    [System.Reflection.Assembly]::LoadFile($bouncyCastleDllPath) | Out-Null
}

function CreateK8sCertSecretYaml() {
    param(
        [string]$CertName,
        [string]$VaultName,
        [string]$K8sSecretName,
        [string]$CertDataKey = "tls.cert",
        [string]$KeyDataKey = "tls.key"
    )

    Initialize-BouncyCastleSupport

    $genevaSecretYaml = $null
    $certificate = $null
    $secret = az keyvault secret show --vault-name $VaultName --name $CertName | ConvertFrom-Json
    if ([bool]($secret.Attributes.PSobject.Properties.name -match "ContentType")) {
        if ($secret.Attributes.ContentType -eq "application/x-pkcs12") {
            $certificate = @{
                data     = $secret.value
                password = ""
            }
        }
    }

    if ($null -eq $certificate) {
        $certificateBytes = [System.Convert]::FromBase64String($secret.value)
        $jsonCertificate = [System.Text.Encoding]::UTF8.GetString($certificateBytes) | ConvertFrom-Json
        $certificate = @{
            data     = $jsonCertificate.data
            password = $jsonCertificate.password
        }
    }

    $pfxFile = New-TemporaryFile
    $crtFile = $pfxFile.FullName + ".crt"
    $keyFile = $pfxFile.FullName + ".key"
    try {
        $data = [System.Convert]::FromBase64String($certificate.data)
        $certObject = New-Object 'System.Security.Cryptography.X509Certificates.X509Certificate2' ($data, $certificate.password, "Exportable")
        $certText = ""
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = "NoCheck"
        [void]$chain.Build($certObject)
        $chain.ChainElements | ForEach-Object {
            $certText += "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($_.Certificate.Export('Cert'), 'InsertLineBreaks') + "`n-----END CERTIFICATE-----`n"
        }
        Set-Content -LiteralPath $crtFile -Value $certText

        $keyPair = [Org.BouncyCastle.Security.DotNetUtilities]::GetRsaKeyPair($certObject.PrivateKey)
        $streamWriter = [System.IO.StreamWriter]$keyFile
        try {
            $pemWriter = New-Object 'Org.BouncyCastle.OpenSsl.PemWriter' ($streamWriter)
            $pemWriter.WriteObject($keyPair.Private)
        }
        finally {
            $streamWriter.Dispose()
        }

        LogInfo -Message "Generate yaml for '$K8sSecretName' as cert"
        $certContent = (Get-Content -LiteralPath $crtFile -Raw).Replace("`r`n", "`n")
        $keyContent = (Get-Content -LiteralPath $keyFile -Raw).Replace("`r`n", "`n")
        $genevaSecretYaml = @"
---
apiVersion: v1
kind: Secret
metadata:
  name: $($K8sSecretName)
data:
  $($CertDataKey): $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($certContent)))
  $($KeyDataKey): $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($keyContent)))
type: Opaque
"@
    }
    finally {
        Remove-Item -LiteralPath $crtFile -Force -ErrorAction Ignore
        Remove-Item -LiteralPath $keyFile -Force -ErrorAction Ignore
        Remove-Item -LiteralPath $pfxFile -Force -ErrorAction Ignore
    }

    return $genevaSecretYaml
}
