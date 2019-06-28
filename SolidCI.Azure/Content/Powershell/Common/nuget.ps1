#
# invokes the nuget exe
#
function InvokeNugetExe()
{
    Write-Host "$args"
	if("$($env:NUGETEXETOOLPATH)" -eq "") 
	{
	    throw "The NUGETEXETOOLPATH is not set."
	}
    
    return (& $env:NUGETEXETOOLPATH $args) 
}


#
# Returns all the feed sources
#
function GetNugetSources()
{
    $sources=@{}
    $res=InvokeNugetExe "sources"
    $res | ForEach-Object {
        #Write-Host "->$_"
        $match=[regex]::Match($_, '(\d+)\.\s(.+)\s\[(.+)\]')
        if($match.Success) {
            $idx = $match.Captures.groups[1].value
            $name = $match.Captures.groups[2].value
            $state = $match.Captures.groups[3].value
            if("$state" -eq "Enabled") {
                $lastName=$name
            }
            #Write-Host "Match $idx $name $state"
        } elseif ("$lastName" -ne "") {
            $sources[$lastName.Trim()] = $_.Trim()
            $lastName = ""
        }
    }
    return $sources
}

#
# Returns all the versions for specified package
#
function GetNugetPackageVersions()
{
    param([string[]] $sourceNames, [string] $name)

    $nugetSources=GetNugetSources
    if($sourceNames -eq $null) {
        $sourceNames=$nugetSources.Keys
    }

    $sources = @()
    $sourceNames | ForEach-Object {
        $sources += $nugetSources[$_]
    }
    $sources=[system.String]::Join(",", $sources)
    Write-Host "$sources"

    $versions = @()
    $res=InvokeNugetExe "list" "-Prerelease" "-AllVersions" "-Source" $sources "id:$name"
    $res | ForEach-Object {
        #Write-Host "->$_"
        $match=[regex]::Match($_, "$name (.+)")
        if($match.Success) {
            $version = $match.Captures.groups[1].value
            $versions += $version
            #Write-Host $version
        }
    }
    return $versions
}

#
# returns true if the supplied version has been released in
# the specified nuget repo. This method does not take the
# semver version into account
#
function IsNugetReleased()
{
    param([string]$sourceName, [string]$name, [string]$version)
    $wantedVersion=GetVersionFromVersionRange $version
    $wantedVersion="$($wantedVersion[0]).$($wantedVersion[1]).$($wantedVersion[2])"
    $versions=GetNugetPackageVersions $sourceName $name
    return $versions.Contains($wantedVersion)
}

#
# Returns the next build version.
#
function GetNugetBuildVersion()
{
    param([string[]]$sourceNames, [string]$name, [string]$version, [string] $semVersuffix)

    if("$semVersuffix" -ne "") 
    {
        $semVersuffix = "-$semVersuffix"
    }

    $wantedVersion=GetVersionFromVersionRange $version
    $wantedVersion="$($wantedVersion[0]).$($wantedVersion[1]).$($wantedVersion[2])$semVersuffix"
    $versions=GetNugetPackageVersions $sourceNames $name
    $nextVersion=0
    $versions | ForEach-Object {
        Write-Host "$_"
        $match=[regex]::Match($_, "$wantedVersion(\d+)")
        if($match.Success) {
            $versionNumber=[int]$match.Captures.Groups[1].Value
            #Write-Host $versionNumber
            if($versionNumber -gt $nextVersion) {
                $nextVersion = $versionNumber
            }
        }
    }
    $nextVersion = $nextVersion + 1
    return "$($wantedVersion)$(FormatNugetString "{0:000}" $nextVersion)"
}

function FormatNugetString {
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

function GetVersionVal
{
    param([System.Text.RegularExpressions.Match] $match, [int] $idx)
    return [int] ($match.Groups[$idx].Value)
}

function GetVersionFromVersionRange
{
    param([string]$versionRange)
    #Write-Host "$versionRange"
    $match=[regex]::Match("$versionRange", "^(\d+)[.](\d+)[.](\d+)(?:.\d+)*-master(\d+)")
    if($match.Success) {
        return @((GetVersionVal $match 1), (GetVersionVal $match 2),(GetVersionVal $match 3), (GetVersionVal $match 4))
    }
    $match=[regex]::Match("$versionRange", "^(\d+)[.](\d+)[.](\d+)(?:.\d+)*-build(\d+)")
    if($match.Success) {
        return @((GetVersionVal $match 1), (GetVersionVal $match 2),(GetVersionVal $match 3), (GetVersionVal $match 4))
    }
    $match=[regex]::Match("$versionRange", "^(\d+)[.](\d+)[.](\d+)(?:.\d+)*.build(\d+)")
    if($match.Success) {
        return @((GetVersionVal $match 1), (GetVersionVal $match 2),(GetVersionVal $match 3), (GetVersionVal $match 4))
    }
    $match=[regex]::Match("$versionRange", "^(\d+)[.](\d+)[.](\d+)[.](\d+)(?:.\d+)*")
    if($match.Success) {
        return @((GetVersionVal $match 1), (GetVersionVal $match 2),(GetVersionVal $match 3), (GetVersionVal $match 4))
    }
    $match=[regex]::Match("$versionRange", "^(\d+)[.](\d+)[.](\d+)(?:.\d+)*")
    if($match.Success) {
        return @((GetVersionVal $match 1), (GetVersionVal $match 2),(GetVersionVal $match 3), 0)
    }
    $match=[regex]::Match("$versionRange", "^[a-zA-Z]+-(\d+).build(\d+)")
    if($match.Success) {
        return @(0, 0, (GetVersionVal $match 1), (GetVersionVal $match 2))
    }
    $match=[regex]::Match("$versionRange", "^[a-zA-Z]+-(\d+)-build(\d+)")
    if($match.Success) {
        return @(0, 0, (GetVersionVal $match 1), (GetVersionVal $match 2))
    }
    return $null
    #Write-Host $match.captures
}

