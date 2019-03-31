function ConvertValue {
    param(
        [string]$s
    )
    
    [int]$i = $null
    if ([int32]::TryParse($s , [ref]$i )) {
        return $i
    }
    
    $d=Get-Date
    if ([DateTime]::TryParse($s , [ref]$d )) {
        return $d
    }

    return $s
}

function FormatString {
    param(
        [string]$pattern,
        [object[]]$patterArgs
    )

    

    $result=$pattern
    for($i = 0; $i -lt $patterArgs.Length; $i++) {
        $argPattern="\{$i(:[^\}]+)*\}"
        $regex=New-Object System.Text.RegularExpressions.Regex($argPattern)
        $match = $regex.Match($pattern)
        if(!$match.Success) {
            Write-Host "Cannot find match for argument $i using pattern $argPattern"
            continue
        } else {
            #Write-Host "Found match for argument $i using pattern $argPattern"
        }

        $patternArgConverted=ConvertValue $patterArgs[$i]
        $argFormat=$match.Groups[1]
        $formattedArg="{0$argFormat}" -f $patternArgConverted
        #Write-Host $formattedArg
        
        $result=$result.Replace($match.Value, $formattedArg)
    }
    return $result
}

#FormatString -patterArgs @("1", "1975-01-02", "test2") -pattern "{0:000}{1:yyyy-MM-dd}{2}"

function Get-ComplexPattern {
    param(
        [string]$simplePattern
    )
    $complexPattern=$simplePattern
    $complexPattern=$complexPattern.replace("[", "\[")
    $complexPattern=$complexPattern.replace("]", "\]")
    $complexPattern=$complexPattern.replace(")", "\)")
    $complexPattern=$complexPattern.replace("(", "\(")

    $char=$complexPattern[$complexPattern.IndexOf('*')+1]

    $complexPattern="("+$complexPattern.Replace("*", ")[^$char]*(")+")"

    Write-Host " Get complex pattern: $simplePattern->$complexPattern"
    return $complexPattern
}

function ProcessFile {
    param(
        [string]$fileName,
        [string]$replaceSimplePatterns,
        [string]$newtext
    )
    Write-Host "Processing file $fileName. Replacing $replaceSimplePatterns with $newtext"
    $content=Get-Content $fileName

    $simplePatterns=$replaceSimplePatterns.Split(";")
    foreach($simplePattern in $simplePatterns)
    {
        Write-Host " Using pattern $simplePattern"
        $replaceRegex=Get-ComplexPattern -simplePattern $simplePattern
        $regex=New-Object System.Text.RegularExpressions.Regex($replaceRegex)
        $match=$regex.Match($content)
        if(!$match.Success) {
            Write-Host "  No matches found"
            return $false
        }
        while($match.Success) 
        {    
            if($match.Groups.Count -ne 3) {
                Write-Host "  File replace pattern does not contain three groups"
                return $false
            }

            $oldTxt=$match.Value
            $newTxt=$match.Groups[1].Value + $newtext + $match.Groups[2].Value
            Write-Host "  Applying transformation $oldTxt -> $newTxt"
            $content=$content.Replace($oldTxt,$newTxt)
            $match=$match.NextMatch()
        }
    }

    Set-Content -Path $fileName -Value $content

    return $true
}
