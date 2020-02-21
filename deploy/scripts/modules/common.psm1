
function ToFile() {
    # this replaces Out-File built-function that adds a stupid new line
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputString,

        [Parameter(Position = 1)]
        [string]$File
    )

    if (Test-Path $File) {
        Remove-Item $File -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($File, $InputString)
}

function Retry {
    [CmdletBinding()]
    param(
        [int]$MaxRetries = 3,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [int]$RetryDelay = 10,
        [bool]$LogError = $true
    )

    $isSuccessful = $false
    $retryCount = 0
    $prevErrorActionPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    while (!$IsSuccessful -and $retryCount -lt $MaxRetries) {
        try {
            $ScriptBlock.Invoke()
            $isSuccessful = $true
        }
        catch {
            $retryCount++

            if ($LogError) {
                LogInfo -Message $_.Exception.InnerException.Message
                LogInfo -Message "failed after $retryCount attempt, wait $RetryDelay seconds and retry"
            }

            Start-Sleep -Seconds $RetryDelay
        }
    }
    $ErrorActionPreference = $prevErrorActionPref
    return $isSuccessful
}

function Login() {
    param (
        [string] $SubscriptionName,
        [string] $TenantId
    )

    $azAccount = az account show | ConvertFrom-Json
    if ($null -ne $azAccount -and $azAccount.name -eq $SubscriptionName -and $azAccount.tenantId -eq $TenantId) {
        return $azAccount
    }

    if ($null -eq $SubscriptionName -or $SubscriptionName -eq "") {
        throw "SubscriptionName not found in environment variable"
    }

    $clientId = [System.Environment]::GetEnvironmentVariable("ARM_CLIENT_ID", "Process")
    if ($null -ne $clientId) {
        Write-Host "Found service principal id: $clientId"
    }
    $clientSecret = [System.Environment]::GetEnvironmentVariable("ARM_CLIENT_SECRET", "Process")
    if ($null -eq $clientSecret) {
        $mountedClientSecretFile = "/azp/.secrets/.arm_client_secret"
        if (Test-path $mountedClientSecretFile) {
            Write-Host "found secret file: $mountedClientSecretFile"
            $clientSecret = [System.IO.File]::ReadAllText($mountedClientSecretFile)
        }
    }
    if ($null -eq $clientId -or $null -eq $clientSecret) {
        LoginAzureAsUser -SubscriptionName $SubscriptionName -TenantId $TenantId
    }
    else {
        az login --service-principal `
            --username $clientId `
            --password $clientSecret `
            --tenant $TenantId | Out-Null
        az account set -s $SubscriptionName | Out-Null
        $azAccountFromSpn = az account show | ConvertFrom-Json
        return $azAccountFromSpn
    }
}

function LoginAzureAsUser {
    param (
        [string] $SubscriptionName,
        [string] $TenantId
    )

    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount) {
        az login --use-device-code | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }
    elseif ($azAccount.user.type -eq "servicePrincipal") {
        az login --use-device-code | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }
    elseif ($azAccount.tenantId -eq $TenantId -and $azAccount.name -ne $SubscriptionName) {
        LogInfo -Message "switch to subscription $SubscriptionName"
        az account set --subscription $SubscriptionName | Out-Null
    }
    elseif ($azAccount.tenantId -eq $TenantId -and $azAccount.name -eq $SubscriptionName) {
        # already logged in
    }
    else {
        az login --use-device-code | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }

    $currentAccount = az account show | ConvertFrom-Json
    return $currentAccount
}

function TranslateToLinuxFilePath() {
    param(
        [string]$FilePath = "C:/work/github/container/bedrock-lab/scripts/temp/aamva/flux-deploy-key"
    )

    $isWindowsOs = ($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -eq "Win32NT")
    if ($isWindowsOs) {
        # this is for running inside WSL
        $FilePath = $FilePath.Replace("\", "/")
        $driveLetter = Split-Path $FilePath -Qualifier
        $driveLetter = $driveLetter.TrimEnd(':')
        return $FilePath.Replace("$($driveLetter):", "/mnt/$($driveLetter.ToLower())")
    }

    return $FilePath
}

function StripSpaces() {
    param(
        [ValidateSet("key", "pub")]
        [string]$FileType,
        [string]$FilePath
    )

    $fileContent = Get-Content $FilePath -Raw
    $fileContent = $fileContent.Replace("`r", "")
    if ($FileType -eq "key") {
        # 3 parts
        $parts = $fileContent.Split("`n")
        if ($parts.Count -gt 3) {
            $builder = New-Object System.Text.StringBuilder
            $lineNumber = 0
            $parts | ForEach-Object {
                if ($lineNumber -eq 0) {
                    $builder.AppendLine($_) | Out-Null
                }
                elseif ($lineNumber -eq $parts.Count - 1) {
                    $builder.Append("`n$_") | Out-Null
                }
                else {
                    $builder.Append($_) | Out-Null
                }
                $lineNumber++
            }
            $fileContent = $builder.ToString()
        }
    }

    $fileContent | ToFile -File $FilePath
}

function New-CrcTable {
    [uint32]$c = $null
    $crcTable = New-Object 'System.Uint32[]' 256

    for ($n = 0; $n -lt 256; $n++) {
        $c = [uint32]$n
        for ($k = 0; $k -lt 8; $k++) {
            if ($c -band 1) {
                $c = (0xEDB88320 -bxor ($c -shr 1))
            }
            else {
                $c = ($c -shr 1)
            }
        }
        $crcTable[$n] = $c
    }

    Write-Output $crcTable
}

function Update-Crc ([uint32]$crc, [byte[]]$buffer, [int]$length, $crcTable) {
    [uint32]$c = $crc

    for ($n = 0; $n -lt $length; $n++) {
        $c = ($crcTable[($c -bxor $buffer[$n]) -band 0xFF]) -bxor ($c -shr 8)
    }

    Write-output $c
}

function Get-CRC32 {
    <#
        .SYNOPSIS
            Calculate CRC.
        .DESCRIPTION
            This function calculates the CRC of the input data using the CRC32 algorithm.
        .EXAMPLE
            Get-CRC32 $data
        .EXAMPLE
            $data | Get-CRC32
        .NOTES
            C to PowerShell conversion based on code in https://www.w3.org/TR/PNG/#D-CRCAppendix

            Author: Øyvind Kallstad
            Date: 06.02.2017
            Version: 1.0
        .INPUTS
            byte[]
        .OUTPUTS
            uint32
        .LINK
            https://communary.net/
        .LINK
            https://www.w3.org/TR/PNG/#D-CRCAppendix

    #>
    [CmdletBinding()]
    param (
        # Array of Bytes to use for CRC calculation
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [byte[]]$InputObject
    )

    $dataArray = @()
    $crcTable = New-CrcTable
    foreach ($item  in $InputObject) {
        $dataArray += $item
    }
    $inputLength = $dataArray.Length
    Write-Output ((Update-Crc -crc 0xffffffffL -buffer $dataArray -length $inputLength -crcTable $crcTable) -bxor 0xffffffffL)
}

function GetHash() {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputString
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hasCode = Get-CRC32 $bytes
    $hex = "{0:x}" -f $hasCode
    return $hex
}

function Get-FolderHash {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderPath
    )

    $FolderContent = New-Object System.Text.StringBuilder
    Get-ChildItem $FolderPath -Recurse | Where-Object {
        $filePath = $_.FullName
        if ([System.IO.File]::Exists($filePath)) {
            $fileHash = Get-FileHash $filePath
            $FolderContent.Append("$($filePath)=$($fileHash.Hash)") | Out-Null
        }
    }

    $hex = $FolderContent.ToString() | GetHash
    if ($hex.Length -ge 8) {
        return $hex.Substring(0, 8).ToLower()
    }
    else {
        return $hex.PadRight(8, "0")
    }
}

function ToBase64() {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputString
    )

    return [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($InputString))
}

function FromBase64() {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputString
    )

    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($InputString))
}

function TryGetServicePrincipal() {
    param([string]$Name)

    [array]$spns = az ad sp list --display-name $Name | ConvertFrom-Json
    if ($null -eq $spns -or $spns.Count -eq 0) {
        return $null
    }
    elseif ($spns.Count -gt 1) {
        throw "Duplicated spn found with same name: $Name"
    }

    return $spns[0]
}

function TryGetAadApp() {
    param([string]$Name)

    [array]$apps = az ad app list --display-name $Name | ConvertFrom-Json
    if ($null -eq $apps -or $apps.Count -eq 0) {
        return $null
    }
    elseif ($apps.Count -gt 1) {
        throw "Duplicated app found with same name: $Name"
    }

    return $apps[0]
}

function ParseFixedLengthTable() {
    param(
        [string]$InputText,
        [string[]]$ColumnHeaders=@("REPOSITORY", "TAG", "IMAGE ID", "CREATED", "SIZE")
    )

    $lines = $InputText.Split("`n")
    $topLine = $lines[0]
    $columns = New-Object System.Collections.ArrayList
    $ColumnHeaders | ForEach-Object {
        $pos = $topLine.IndexOf($_)
        if ($pos -lt 0) {
            throw "Unable to find header $_ in $topLine"
        }

        $column = @{
            Name = $_
            Pos  = $pos
            Len  = $_.Length
        }
        if ($column.Pos -gt 0) {
            $prevColumn = $columns[$columns.Count - 1]
            $prevColumn.Len = $column.Pos - $prevColumn.Pos
        }
        $columns.Add($column) | Out-Null
    }
    # rm last column length
    $lastColumn = $columns[$columns.Count - 1]
    $lastColumn.Len = -1

    $table = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $record = @{ }
        $line = $lines[$i]
        $columns | ForEach-Object {
            if ($_.Len -gt 0) {
                $value = $line.Substring($_.Pos, $_.Len)
            }
            else {
                $value = $line.Substring($_.Pos)
            }
            $record[$_.Name] = $value
        }
        $table.Add($record) | Out-Null
    }

    return $table
}