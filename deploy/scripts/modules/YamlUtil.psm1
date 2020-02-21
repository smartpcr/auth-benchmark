

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$deployFolder = Join-Path $gitRootFolder "deploy"
$scriptFolder = Join-Path $deployFolder "scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

# Import-Module "$scriptFolder\Modules\powershell-yaml\powershell-yaml.psm1" -Force
Install-Module powershell-yaml -AllowClobber -Confirm:$false -Force
Import-Module powershell-yaml -Force -DisableNameChecking

function Copy-YamlObject {
    param (
        [object] $FromObj,
        [object] $ToObj
    )

    # handles array assignment
    if ($FromObj.GetType().IsGenericType -and $ToObj.GetType().IsGenericType) {
        HandleArrayOverride -FromObj $FromObj -ToObj $ToObj
        return
    }

    $FromObj.Keys | ForEach-Object {
        $name = $_
        $value = $FromObj.Item($name)

        if ($null -ne $value) {
            $tgtName = $ToObj.Keys | Where-Object { $_ -eq $name }
            if ($null -eq $tgtName) {
                $ToObj.Add($name, $value) | Out-Null
            }
            else {
                $tgtValue = $ToObj.Item($tgtName)
                if ($value -is [string] -or $value -is [int] -or $value -is [bool]) {
                    if ($value -ne $tgtValue) {
                        # Write-Host "Change value for '$tgtName' from '$tgtValue' to '$value'" -ForegroundColor Green
                        $ToObj[$tgtName] = $value
                    }
                }
                else {
                    if ($value.GetType().IsGenericType -and $tgtValue.GetType().IsGenericType) {
                        # Write-Host "handle array override: '$tgtName'" -ForegroundColor Yellow
                        HandleArrayOverride -FromObj $value -ToObj $tgtValue
                    }
                    else {
                        # Write-Host "handle child override: '$tgtName'" -ForegroundColor Yellow
                        Copy-YamlObject -fromObj $value -toObj $tgtValue
                    }
                }
            }
        }
    }
}

function HandleArrayOverride() {
    param(
        [object] $FromObj,
        [object] $ToObj
    )

    if ($null -ne $FromObj -and $FromObj.GetType().IsGenericType -and $null -ne $ToObj -and $ToObj.GetType().IsGenericType) {
        [array]$fromArray = [array]$FromObj
        [array]$toArray = [array]$ToObj
        if ($fromArray.Length -gt 0 -and $toArray.Length -gt 0) {
            $hasNameKey = $true
            $hasKey = $true
            $fromArray | ForEach-Object {
                if ($null -eq $_["name"]) {
                    $hasNameKey = $false
                }
                if ($null -eq $_["key"]) {
                    $hasKey = $false
                }
            }
            $toArray | ForEach-Object {
                if ($null -eq $_["name"]) {
                    $hasNameKey = $false
                }
                if ($null -eq $_["key"]) {
                    $hasKey = $false
                }
            }

            $keyPropName = $null
            if ($hasNameKey) {
                $keyPropName = "name"
            }
            elseif ($hasKey) {
                $keyPropName = "key"
            }

            if ($null -ne $keyPropName) {
                $unionList = New-Object System.Collections.ArrayList
                $toArray | ForEach-Object {
                    $toArrayChild = $_
                    $toName = $toArrayChild[$keyPropName]
                    $fromArrayChild = $fromArray | Where-Object { $_[$keyPropName] -eq $toName }
                    if ($null -ne $fromArrayChild) {
                        # Write-Host "Handle child override '$toName'" -ForegroundColor Yellow
                        Copy-YamlObject -FromObj $fromArrayChild -ToObj $toArrayChild
                    }
                    $unionList.Add($toArrayChild) | Out-Null
                }
                $fromArray | ForEach-Object {
                    $fromArrayChild = $_
                    $fromName = $fromArrayChild[$keyPropName]
                    $toArrayChild = $toArray | Where-Object { $_[$keyPropName] -eq $fromName }
                    if ($null -eq $toArrayChild) {
                        # Write-Host "Add new child '$fromName'" -ForegroundColor Green
                        $unionList.Add($fromArrayChild) | Out-Null
                    }
                }
                $toArray = $unionList.ToArray()
            }
            else {
                $toArray = $fromArray
            }
        }
    }
}

function Set-YamlValues {
    param (
        [string] $ValueTemplate,
        [object] $Settings
    )

    $regex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.([a-zA-Z\.0-9_]+)\s*\}\}")
    $replacements = New-Object System.Collections.ArrayList
    $match = $regex.Match($ValueTemplate)
    while ($match.Success) {
        $toBeReplaced = $match.Value
        $searchKey = $match.Groups[1].Value

        $found = GetPropertyValue -subject $Settings -propertyPath $searchKey
        if ($found) {
            if ($found -is [string] -or $found -is [int] -or $found -is [bool]) {
                $replaceValue = $found.ToString()
                $replacements.Add(@{
                        oldValue = $toBeReplaced
                        newValue = $replaceValue
                    }) | Out-Null
            }
            else {
                Write-Warning "Invalid value for path '$searchKey': $($found | ConvertTo-Json)"
            }
        }
        else {
            # Write-Warning "Unable to find value with path '$searchKey'"
        }

        $match = $match.NextMatch()
    }

    $replacements | ForEach-Object {
        $oldValue = $_.oldValue
        $newValue = $_.newValue
        # Write-Host "Replacing '$oldValue' with '$newValue'" -ForegroundColor Yellow
        $ValueTemplate = $ValueTemplate.Replace($oldValue, $newValue)
    }

    return $ValueTemplate
}

function ReplaceValuesInYamlFile {
    param(
        [string] $YamlFile,
        [string] $PlaceHolder,
        [string] $Value
    )

    $content = ""
    if (Test-Path $YamlFile) {
        $content = Get-Content $YamlFile
    }

    $pattern = "\{\{\s*\.Values.$PlaceHolder\s*\}\}"
    $buffer = New-Object System.Text.StringBuilder
    $content | ForEach-Object {
        $line = $_
        if ($line) {
            $line = $line -replace $pattern, $Value
            $buffer.AppendLine($line) | Out-Null
        }
    }

    $buffer.ToString() | ToFile -File $YamlFile
}

function GetPropertyValue {
    param(
        [object]$subject,
        [string]$propertyPath
    )

    $propNames = $propertyPath.Split(".")
    $currentObject = $subject
    for ($i = 0; $i -lt $propNames.Count; $i++) {
        $propName = $propNames[$i]
        if ($null -eq $currentObject -or $null -eq $propName) {
            return $null
        }
        if (IsPrimitiveValue -inputValue $currentObject) {
            Write-Warning "Unable to get property '$propName' using propertyPath='$propertyPath', current value is '$currentObject'"
            return $null
        }

        if ($null -ne $currentObject -and ([hashtable]$currentObject).ContainsKey($propName)) {
            $currentObject = $currentObject[$propName]

            if ($i -eq $propNames.Count - 1) {
                return $currentObject
            }
        }
        else {
            return $null
        }
    }
}

function GetProperties {
    param(
        [object] $subject,
        [string] $parentPropName
    )

    Write-Verbose "getting props under $parentPropName"
    $props = New-Object System.Collections.ArrayList
    if ($null -eq $subject) {
        return $props
    }

    # handles array assignment
    if (($subject.GetType().IsGenericType) -or ($subject -is [array])) {
        $propName = if ($parentPropName) { $parentPropName } else { "" }
        $props.Add($propName) | Out-Null
        return $props
    }

    try {
        $dummy = $subject.Keys
        if ($null -eq $dummy) {
            Write-Warning "Unable to get props under $parentPropName"
            return $props
        }
    }
    catch {
        Write-Warning "Unable to get props under $parentPropName"
        return $props
    }

    $subject.Keys | ForEach-Object {
        $currentPropName = $_
        $value = $subject[$currentPropName]

        if ($null -ne $value) {
            $propName = $currentPropName
            if ($null -ne $parentPropName -and $parentPropName.Length -gt 0) {
                $propName = $parentPropName + "." + $currentPropName
            }

            if (IsPrimitiveValue -inputValue $value) {
                $props.Add($propName) | Out-Null
            }
            else {
                $nestedProps = GetProperties -subject $value -parentPropName $propName
                if ($null -ne $nestedProps) {
                    if ($nestedProps -is [string]) {
                        $props.Add([string]$nestedProps) | Out-Null
                    }
                    else {
                        $nestedProps | ForEach-Object {
                            $props.Add($_) | Out-Null
                        }
                    }
                }
            }
        }
    }

    return $props
}

function IsPrimitiveValue {
    param([object] $inputValue)

    if ($null -eq $inputValue) {
        return $true
    }

    $type = $inputValue.GetType()
    if ($type.IsPrimitive -or $type.IsEnum -or $type.Name -ieq "string") {
        return $true
    }

    return $false;
}

function EnsureParentProperty {
    param(
        [object] $targetObject,
        [string] $propertyPath
    )

    $propNames = $propertyPath.Split(".")
    $currentValue = $targetObject
    if ($currentValue.GetType().IsGenericType) {
        return
    }

    $index = 0
    while ($index -lt $propNames.Count) {
        $propName = $propNames[$index]
        $child = $currentValue[$propName]
        if ($null -eq $child) {
            if ($index -lt $propNames.Count - 1) {
                $child = @{ }
                $currentValue[$propName] = $child
                $currentValue = $currentValue[$propName]
            }
            else {
                return
            }
        }
        else {
            $currentValue = $child
        }
        if ($currentValue.GetType().IsGenericType) {
            return
        }
        $index++
    }
}

function SetPropertyValue {
    param(
        [object] $targetObject,
        [string] $propertyPath,
        [object] $propertyValue,
        [switch] $AllowOverride
    )

    if ($null -eq $targetObject) {
        return
    }

    EnsureParentProperty -targetObject $targetObject -propertyPath $propertyPath

    $propNames = $propertyPath.Split(".")
    $currentValue = $targetObject
    $index = 0
    while ($index -lt $propNames.Count) {
        $propName = $propNames[$index]

        if ($index -eq $propNames.Count - 1) {
            # $oldValue = $currentValue[$propName]
            if ((-not ($propertyValue.GetType().IsGenericType)) -and $currentValue.GetType().IsGenericType) {
                if (([array]$currentValue).Count -eq 0) {
                    Write-Verbose "creating first element of array, $propName=$propertyValue"
                    $currentValue = @(
                        @{
                            $propName = $propertyValue
                        }
                    )
                    Write-Verbose ($currentValue | ConvertTo-Json -Compress)
                }
                elseif (([array]$currentValue).Count -eq 1) {
                    Write-Verbose "add additional prop to first element of array, $propName=$propertyValue"
                    $firstItem = $currentValue[0]
                    $firstItem[$propName] = $propertyValue
                    Write-Verbose ($currentValue | ConvertTo-Json -Compress)
                }
                else {
                    Write-Verbose "shrinking array, $propName=$propertyValue"
                    $firstItem = $currentValue[0]
                    $firstItem[$propName] = $propertyValue
                    $currentValue = @($firstItem)
                    Write-Verbose ($currentValue | ConvertTo-Json -Compress)
                }
            }
            else {
                $currentValue[$propName] = $propertyValue
            }
            if ($Verbose) {
                Write-Verbose "`tChange value for property '$propertyPath' from '$oldValue' to '$propertyValue'" -ForegroundColor White
            }

            return
        }
        else {
            $currentValue = $currentValue[$propName]
            if ($null -eq $currentValue) {
                # Write-Warning "Unable to find property with path '$propertyPath'"
                if ($AllowOverride) {
                    $currentValue[$propName] = $propValue
                    Write-Verbose "`tSet value for property '$propName' from '$null' to '$propValue'" -ForegroundColor White
                }
                return
            }
        }

        $index++
    }
}

function GetInnerFunctionExpression() {
    param(
        [string] $InputToEvaluate,
        [object] $InputObject = $null
    )

    $pipeFuncExprRegex = New-Object System.Text.RegularExpressions.Regex("\`$\(([^|`$]+)\s+\|\s+([^|\`$]+)\)")
    $funcExprRegex = New-Object System.Text.RegularExpressions.Regex("\`$\((\w+)\s*([^\|()\`$]*)\)")

    $match1 = $pipeFuncExprRegex.Match($InputToEvaluate)
    if ($match1.Success) {
        $match2 = $funcExprRegex.Match($match1.Groups[2].Value)
        if ($match2.Success) {
            return @{
                Value        = $match1.Value
                Feeder       = $match1.Groups[1].Value
                FunctionName = $match2.Groups[1].Value
                ArgList      = $match2.Groups[2].Value
            }
        }
        else {
            return @{
                Value        = $match1.Value
                Feeder       = $match1.Groups[1].Value
                FunctionName = $match1.Groups[2].Value
                ArgList      = $null
                Result       = $null
            }
        }
    }

    $match2 = $funcExprRegex.Match($InputToEvaluate)
    if ($match2.Success) {
        return @{
            Value        = $match2.Value
            FunctionName = $match2.Groups[1].Value
            ArgList      = $match2.Groups[2].Value
            Result       = $null
        }
    }

    if ($null -ne $InputObject) {
        $expressionBuilder = New-Object System.Text.StringBuilder
        $expressionBuilder.AppendLine("param(`$InputObject)") | Out-Null
        $expressionBuilder.AppendLine("return " + $InputToEvaluate) | Out-Null
        $scriptContent = $expressionBuilder.ToString()
        # Write-Host "Executing script block: `n$scriptContent`n" -ForegroundColor White
        $scriptBlock = [Scriptblock]::Create($scriptContent)
        $execResult = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $InputObject
        return @{
            Value        = $InputToEvaluate
            FunctionName = $null
            ArgList      = $null
            Result       = $execResult
        }
    }

    return $null
}

function Evaluate() {
    param(
        [string] $InputToEvaluate
    )

    $innerFunctionExpression = GetInnerFunctionExpression -InputToEvaluate $InputToEvaluate
    $evaluationResult = $null
    while ($null -ne $innerFunctionExpression) {
        if ($null -ne $innerFunctionExpression.Result) {
            $evaluationResult = $innerFunctionExpression.Result
        }
        else {
            $evaluationResult = EvaluateFunctionExpression -FunctionExpression $innerFunctionExpression -InputObject $evaluationResult
        }

        if ($evaluationResult) {
            if (IsPrimitiveValue -InputValue $evaluationResult) {
                # Write-Host "Replacing '$($innerFunctionExpression.Value)' with '$evaluationResult'" -ForegroundColor Yellow
                $InputToEvaluate = $InputToEvaluate.Replace($innerFunctionExpression.Value, "`"$evaluationResult`"")
                $innerFunctionExpression = GetInnerFunctionExpression -InputToEvaluate $InputToEvaluate
            }
            else {
                $InputObjectJson = $evaluationResult | ConvertTo-Json

                # Write-Host "Replacing '$($innerFunctionExpression.Value)' with json: `n$InputObjectJson`n" -ForegroundColor Yellow
                $InputToEvaluate = $InputToEvaluate.Replace($innerFunctionExpression.Value, "`$InputObject")
                $innerFunctionExpression = GetInnerFunctionExpression -InputToEvaluate $InputToEvaluate -InputObject $evaluationResult
            }
        }
        else {
            $innerFunctionExpression = $null
        }
    }

    return $InputToEvaluate
}

function EvaluateFunctionExpression() {
    param(
        [Parameter(Mandatory = $true)]
        [object] $FunctionExpression,
        [object] $InputObject = $null
    )

    $expressionBuilder = New-Object System.Text.StringBuilder
    if ($null -ne $InputObject) {
        $expressionBuilder.AppendLine("param(`$InputObject)") | Out-Null
    }
    $expressionBuilder.AppendLine("return " + $FunctionExpression.Value) | Out-Null
    $scriptContent = $expressionBuilder.ToString()
    # Write-Host "Executing script block: `n$scriptContent`n" -ForegroundColor White
    $scriptBlock = [Scriptblock]::Create($scriptContent)

    if ($null -ne $InputObject) {
        $execResult = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $InputObject
    }
    else {
        $execResult = Invoke-Command -ScriptBlock $scriptBlock
    }
    # Write-Host "Script result: $execResult" -ForegroundColor White

    return $execResult
}

function GetFunctionExpressions {
    param(
        [string] $YamlContent
    )

    $functionList = New-Object System.Collections.ArrayList
    $funcStartRegex = New-Object System.Text.RegularExpressions.Regex("\$\(")
    $lastFuncEndPos = 0
    $funcMatch = $funcStartRegex.Match($yamlContent, $lastFuncEndPos)
    while ($funcMatch.Success) {
        $parenthesisStack = New-Object System.Collections.Stack
        $pos = $funcMatch.Index
        $foundFuncExpr = $false

        while ($pos -lt $yamlContent.Length -and !$foundFuncExpr) {
            $currentChar = $yamlContent[$pos]
            if ($currentChar -eq "(") {
                $parenthesisStack.Push($currentChar)
            }
            elseif ($currentChar -eq ")") {
                if ($parenthesisStack.Count -lt 1) {
                    throw "Invalid function expression at $pos"
                }
                $parenthesisStack.Pop() | Out-Null

                if ($parenthesisStack.Count -eq 0) {
                    $lastFuncEndPos = $pos + 1
                    $functionExpr = $yamlContent.Substring($funcMatch.Index, $lastFuncEndPos - $funcMatch.Index)
                    if ($functionExpr -ne $YamlContent) {
                        # Write-Host "Found function: $functionExpr" -ForegroundColor White
                        $functionList.Add($functionExpr) | Out-Null
                    }

                    $lastFuncEndPos = $pos + 1
                    $foundFuncExpr = $true
                }
            }
            $pos++
        }

        $funcMatch = $funcStartRegex.Match($yamlContent, $lastFuncEndPos)
    }

    return @($functionList.ToArray())
}

function UpdateYamlWithEmbeddedFunctions {
    param(
        [string] $YamlFile
    )

    $yamlContent = Get-Content $YamlFile -Raw
    $funcExpressions = GetFunctionExpressions -YamlContent $yamlContent
    foreach ($functionInput in $funcExpressions) {
        $evaluatedValue = Evaluate -InputToEvaluate $functionInput
        if ($evaluatedValue -and $(IsPrimitiveValue -InputValue $evaluatedValue)) {
            $evaluatedValue = $evaluatedValue.Trim("`"")
            # Write-Host "$functionInput -> $evaluatedValue"
            $yamlContent = $yamlContent.Replace($functionInput, $evaluatedValue)
        }
        else {
            Write-Warning "Invalid value for function: $functionInput"
        }
    }

    $yamlContent | ToFile -File $YamlFile
}

function EvaluateEmbeddedFunctions() {
    param(
        [string] $YamlContent,
        [object] $InputObject
    )

    $funcRegex = New-Object System.Text.RegularExpressions.Regex("^\s*(\S+)\:\s*['`"](.*\`$\(.+\).+)['`"]$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $bindingRegex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.([a-zA-Z\.0-9_]+)\s*\}\}", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $replacements = New-Object System.Collections.ArrayList

    $funcMatch = $funcRegex.Match($YamlContent)
    while ($funcMatch.Success) {
        $originalValue = $funcMatch.Groups[2].Value.Trim("`"").Trim("'")
        $settingValue = $originalValue
        $bindingMatch = $bindingRegex.Match($settingValue)
        $parameters = New-Object System.Collections.ArrayList

        while ($bindingMatch.Success) {
            $toBeReplaced = $bindingMatch.Value
            $searchKey = $bindingMatch.Groups[1].Value
            $found = GetPropertyValue -subject $InputObject -propertyPath $searchKey
            if ($null -ne $found) {
                if ($found -is [string] -or $found -is [int] -or $found -is [bool]) {
                    $replaceValue = $found.ToString()
                    $settingValue = $settingValue.Replace($toBeReplaced, $replaceValue)
                }
                else {
                    $paramName = "`$param" + ($parameters.Count + 1);
                    $param = @{
                        name  = $paramName
                        value = $found
                    }
                    $parameters.Add($param) | Out-Null
                    $settingValue = $settingValue.Replace($toBeReplaced, $paramName)
                }
            }
            else {
                # Write-Warning "Unable to find value with path '$searchKey'"
            }

            $bindingMatch = $bindingMatch.NextMatch()
        }

        $expressionBuilder = New-Object System.Text.StringBuilder
        if ($parameters.Count -gt 0) {
            $expressionBuilder.AppendLine("param(") | Out-Null
            $parameterIndex = 0
            $parameters | ForEach-Object {
                if ($parameterIndex -lt ($parameters.Count - 1)) {
                    $expressionBuilder.AppendLine("`t$($_.name),") | Out-Null
                    $parameterIndex++
                }
                else {
                    $expressionBuilder.AppendLine("`t$($_.name)") | Out-Null
                }
            }
            $expressionBuilder.AppendLine(")") | Out-Null
        }
        $expressionBuilder.AppendLine("return `"" + $settingValue + "`"") | Out-Null
        $scriptContent = $expressionBuilder.ToString()

        $scriptBlock = [Scriptblock]::Create($scriptContent)
        $execResult = $null
        if ($parameters.Count -gt 0) {
            $argList = New-Object System.Collections.ArrayList
            $parameters | ForEach-Object {
                $argList.Add($_.value) | Out-Null
            }
            $execResult = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $argList
        }
        else {
            $execResult = Invoke-Command -ScriptBlock $scriptBlock
        }

        if ($null -ne $execResult) {
            $replacements.Add(@{
                    oldValue = $originalValue
                    newValue = $execResult.ToString()
                }) | Out-Null
        }

        $funcMatch = $funcMatch.NextMatch()
    }

    $replacements | ForEach-Object {
        $oldValue = $_.oldValue
        $newValue = $_.newValue
        # Write-Host "Replacing '$oldValue' with '$newValue'" -ForegroundColor Yellow
        $YamlContent = $YamlContent.Replace($oldValue, $newValue)
    }

    return $YamlContent
}

function ConvertYamlToJson() {
    param(
        [Hashtable] $InputObject,
        [int] $Depth = 0,
        [int] $Indent = 2
    )

    $indentation = "".PadLeft($Depth * $Indent)
    $OutputBuilder = New-Object System.Text.StringBuilder
    $OutputBuilder.Append($indentation + "{") | Out-Null

    $isFirstElement = $true
    $InputObject.Keys | ForEach-Object {
        $name = $_
        $value = $InputObject[$name]

        if ($isFirstElement) {
            $OutputBuilder.Append("`n$($indentation)`"$($name)`": ") | Out-Null
            $isFirstElement = $false
        }
        else {
            $OutputBuilder.Append(",`n$($indentation)`"$($name)`": ") | Out-Null
        }

        if (IsPrimitiveValue -inputValue $value) {
            if ($value -is [string]) {
                $OutputBuilder.Append("`"$($value)`"") | Out-Null
            }
            elseif ($value -is [bool]) {
                if ($value -eq $true) {
                    $OutputBuilder.Append("true") | Out-Null
                }
                else {
                    $OutputBuilder.Append("false") | Out-Null
                }
            }
            elseif ($null -eq $value) {
                $OutputBuilder.Append("null") | Out-Null
            }
            else {
                $OutputBuilder.Append($value) | Out-Null
            }
        }
        elseif ($value.GetType().IsGenericType) {
            $OutputBuilder.Append("[") | Out-Null
            $isFirstItem = $true
            [array]$value | ForEach-Object {
                $arrayItem = $_
                if (IsPrimitiveValue -inputValue $arrayItem) {
                    if (!$isFirstItem) {
                        $OutputBuilder.Append(",") | Out-Null
                    }
                    else {
                        $isFirstItem = $false
                    }

                    if ($arrayItem -is [string]) {
                        $OutputBuilder.Append("`"$($arrayItem)`"") | Out-Null
                    }
                    elseif ($arrayItem -is [bool]) {
                        if ($arrayItem -eq $true) {
                            $OutputBuilder.Append("true") | Out-Null
                        }
                        else {
                            $OutputBuilder.Append("false") | Out-Null
                        }
                    }
                    elseif ($null -eq $arrayItem) {
                        $OutputBuilder.Append("null") | Out-Null
                    }
                    else {
                        $OutputBuilder.Append($arrayItem) | Out-Null
                    }
                }
                else {
                    $arrayItemJson = ConvertYamlToJson -InputObject $_ -Indent $Indent -Depth ($Depth + 1)
                    if ($isFirstItem) {
                        $isFirstItem = $false
                    }
                    else {
                        $arrayItemJson = "," + $arrayItemJson
                    }
                    $OutputBuilder.Append($arrayItemJson) | Out-Null
                }

            }
            $OutputBuilder.Append("`n" + $indentation + "]") | Out-Null
        }
        else {
            $childJson = ConvertYamlToJson -InputObject $value -Indent $Indent -Depth ($Depth + 1)
            $OutputBuilder.Append($childJson) | Out-Null
        }
    }

    $OutputBuilder.Append("`n" + $indentation + "}") | Out-Null

    [string]$json = $OutputBuilder.ToString()
    return $json
}

function OverrideYamlValues() {
    param(
        [ValidateScript( { Test-Path $_ })]
        [string]$YamlFile,
        [ValidateScript( { Test-Path $_ })]
        [string]$SettingsOverrideFile
    )

    $rawBaseYamlContent = Get-Content $YamlFile -Raw
    $baseSettingSections = New-Object System.Collections.ArrayList
    $buffer = New-Object System.Text.StringBuilder
    $rawBaseYamlContent.Split("`n") | ForEach-Object {
        $line = $_
        if ($line -eq "---") {
            if ($buffer.Length -gt 0) {
                $baseSettingSections.Add($buffer.ToString()) | Out-Null
                $buffer = New-Object System.Text.StringBuilder
            }
        }
        else {
            $buffer.AppendLine($line) | Out-Null
        }
    }
    if ($buffer.Length -gt 0) {
        $baseSettingSections.Add($buffer.ToString()) | Out-Null
        $buffer = New-Object System.Text.StringBuilder
    }

    $baseSettings = Get-Content $YamlFile -Raw | ConvertFrom-Yaml -Ordered
    $buffer = New-Object System.Text.StringBuilder
    $rawSettingContent = Get-Content $SettingsOverrideFile -Raw
    $rawSettingContent.Split("`n") | ForEach-Object {
        [string]$line = $_
        if ($line -eq "config:") {
            Write-Host "trim: $line"
        }
        elseif ($line -eq "subcomponents:") {
            Write-Host "trim $line"
        }
        elseif ($line.Trim().Length -eq 0) {
            $buffer.AppendLine($line.Trim()) | Out-Null
        }
        elseif ($line.StartsWith("  ")) {
            $line = $line.Substring(2) # remove 1 indentation level
            Write-Host "add: $line"
            $buffer.AppendLine($line) | Out-Null
        }
        else {
            throw "Invalid indentation: $line"
        }
    }
    $settingsOverride = $buffer.ToString() | ConvertFrom-Yaml
    $settingName = [System.IO.Path]::GetFileNameWithoutExtension($YamlFile)
    if ($null -ne $settingsOverride[$settingName]) {
        $settingsOverride = $settingsOverride[$settingName]
        if ($null -ne $settingOverride["config"]) {
            $settingsOverride = $settingsOverride["config"]
        }
    }
    $overrideProps = GetProperties -subject $SettingsOverride

    LogStep -Message "Override property values"
    $overrideProps | ForEach-Object {
        $propPath = $_
        $propValue = GetPropertyValue -subject $settingsOverride -propertyPath $propPath

        # TODO: pick the correct base setting section

        if ($null -ne $propValue -and $propValue -ne "") {
            LogInfo -Message "Set $propPath=$propValue"
            SetPropertyValue -targetObject $baseSettings -propertyPath $propPath -propertyValue $propValue -AllowOverride -Verbose
        }
    }
}

function SplitYamlFile() {
    param(
        [string]$YamlFile
    )

    [string]$rawBaseYamlContent = Get-Content $YamlFile -Raw
    $sections = New-Object System.Collections.ArrayList

    if ($null -ne $rawBaseYamlContent -and $rawBaseYamlContent.Length -gt 0) {
        $buffer = New-Object System.Text.StringBuilder
        $rawBaseYamlContent.Split("`n") | ForEach-Object {
            [string]$line = $_
            if ($line -eq "---") {
                if ($buffer.Length -gt 0) {
                    $sections.Add($buffer.ToString()) | Out-Null
                    $buffer = New-Object System.Text.StringBuilder
                }
            }
            elseif ($line.Trim().StartsWith("#")) {
                # comments
            }
            else {
                $buffer.AppendLine($line) | Out-Null
            }
        }
        if ($buffer.Length -gt 0) {
            $sections.Add($buffer.ToString()) | Out-Null
            $buffer = New-Object System.Text.StringBuilder
        }
    }

    return $sections.ToArray()
}

function GetFluxWorkloadType() {
    param(
        [string]$YamlSection
    )

    $YamlSection.Split("`n") | ForEach-Object {
        [string]$line = $_
        if ($line -match "^\s*kind\:\s+(deployment|cronjob|daemonset|statefulset)$") {
            $workloadType = $Matches[1]
            return $workloadType
        }
    }

    return $null
}

function ResolveSelfReferencedFields() {
    param(
        [object]$Settings
    )

    $regex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.([a-zA-Z\.0-9_]+)\s*\}\}")
    $foundMatch = $false
    $started = $false
    $iterationCount = 0
    while ($foundMatch -and $iterationCount -lt 10 -or !$started) {
        $started = $true
        $foundMatch = $false
        $iterationCount++
        $propertyNames = GetProperties -subject $Settings
        $propertyNames | ForEach-Object {
            $propPath = $_
            $propValue = GetPropertyValue -subject $Settings -propertyPath $propPath
            if ($propValue -is [string] -and $regex.IsMatch($propValue)) {
                $foundMatch = $true
                Write-Verbose "found value reference: $propValue, $foundMatch"
                $referencePath = $regex.Match($propValue).Groups[1].Value
                $replacement = $regex.Match($propValue).Value
                $referencedValue = GetPropertyValue -subject $Settings -propertyPath $referencePath
                if ($null -ne $referencedValue) {
                    Write-Verbose "setting '$propPath'='$referencedValue'"
                    $newPropValue = $propValue.Replace($replacement, $referencedValue)
                    SetPropertyValue -targetObject $Settings -propertyPath $propPath -propertyValue $newPropValue -AllowOverride
                }
            }
        }
    }

    if ($foundMatch) {
        throw "Failed to resolve referenced field"
    }
}