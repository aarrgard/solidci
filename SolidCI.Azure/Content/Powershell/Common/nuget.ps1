
#
# setup feed authorization
#
if("$($env:FEED_PAT)" -ne "") {
	Write-Host "Using basic authorization to access feeds - using PAT"
	$feed_authorization="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($env:FEED_PAT)")))"
} else {
	if($($env:SYSTEM_ACCESSTOKEN) -ne $null) {
		Write-Host "Using bearer authorization to access feeds - using system accesstoken"
		$feed_authorization="Bearer $($env:SYSTEM_ACCESSTOKEN)"
	}
}
if($feed_authorization -eq $null) {
	Get-ChildItem Env:
	throw "Cannot determine feed authorization. Please set the FEED_PAT environment variable"
}
Set-variable -Name "FEED_AUTHORIZATION" -Value $feed_authorization -Scope Global 

$feeds=New-Object System.Collections.ArrayList

function InvokeWebRequest()
{
    param([string] $uri)

    Write-Host "Getting data from $uri ..."

    $resp=Invoke-WebRequest -Uri $uri -Headers @{
		"Authorization"=$FEED_AUTHORIZATION
	} -UseBasicParsing

    #Write-Host "Got data:$($resp.Content)"
	$statusCode=$resp.StatusCode
	$acceptedCodes=@(200,203)
	if(-not $($acceptedCodes).Contains($statusCode)) {
		throw "Status code not ok ($statusCode). Should be one of $acceptedCodes"
	}

    $res=$resp.Content | ConvertFrom-Json
    return $res
}

function GetPackages
{
    param([string]$accountName, [string]$feedId)
    #try 
    #{
    #    $res=(Get-Variable -Name "$feedId-packages").Value
    #    if($res) {
    #        return $res
    #    }
    #}
    #catch { }
    $uri="https://$accountName.feeds.visualstudio.com/_apis/packaging/Feeds/$feedId/packages?api-version=4.1-preview&includeAllVersions=true"
    $res=(InvokeWebRequest $uri).Value
    
    $feeds.Add($feedId)

    Set-Variable -Name "$feedId-packages" -Value $res -Scope Global
    return $res
}

function GetPackageVersion
{
    param([string]$accountName, [string]$feedId, [string]$name, [string]$version)
    $packages=GetPackages $accountName $feedId
    $package=$null
    $packageVersion=$null
    $packages | % { 
        if($_.Name -eq $name) {
            $workPackage=$_
            $_.versions | % {
                if($_.Version -eq $version) {
                    $package=$workPackage
                    $packageVersion=$_
                }
            }
        } 
    }

    if(-not $package) {
        Write-Host "Could not find package $name-$version in $feedId"
        return $null
    }
    

    $uri="$($package.url)/Versions/$($packageVersion.id)"
    $res=InvokeWebRequest $uri
    return $res
}

function IsReleased
{
    param([string]$accountName, [string]$feedId, [string]$name, [string]$version)
    $packages=GetPackages $accountName $feedId
    $wantedVersion=GetVersionFromVersionRange $version
    $exists = $false
    $packages | % { 
        if($_.Name -eq $name) {
            #Write-Host "Found package!"
            $_.versions | % {
                $packageVersion=GetVersionFromVersionRange $_.Version
                if($wantedVersion[0] -ne $packageVersion[0]) {
                    return
                }
                if($wantedVersion[1] -ne $packageVersion[1]) {
                    return
                }
                if($wantedVersion[2] -ne $packageVersion[2]) {
                    return
                }
                $exists = $true
            }
        } 
    }
    return $exists
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


function GetNextVersionNumber
{
    param([string]$accountName, [string]$releaseFeedId, [string]$publishFeedId, [string]$name, [string]$version)

    $wantedVersion=GetVersionFromVersionRange $version
    if($wantedVersion -eq $null) {
		#
		# we are probably building from master - 
		# Get the released version, add one to the minor version
		# the the next step will update the "fix" number according to the releases
		# in the publish feed(release/prerelease).
		# 
        $wantedVersion = GetVersionFromVersionRange (GetReleasedVersion $accountName $releaseFeedId $name)
        $wantedVersion[1] = $wantedVersion[1] + 1
        $wantedVersion[2] = 0
        $wantedVersion[3] = 1
    }

    #Write-Host "Getting next available build number for $version->$wantedVersion"

    $packages=GetPackages $accountName $publishFeedId
    $packages | % { 
        if($_.Name -eq $name) {
            #Write-Host "Found package $name"
            $_.versions | % {
                $packageVersion=GetVersionFromVersionRange $_.Version
                if($wantedVersion[0] -ne $packageVersion[0]) {
                    return
                }
                if($wantedVersion[1] -ne $packageVersion[1]) {
                    return
                }
                if($wantedVersion[2] -ne $packageVersion[2]) {
                    return
                }
                #Write-Host "Found build for version $($packageVersion[0]).$($packageVersion[1]).$($packageVersion[2]).$($packageVersion[3])"
                if($packageVersion[3] -ge $wantedVersion[3]) {
                    $wantedVersion[3] = $packageVersion[3] + 1
                }
            }
        } 
    }
    return "$($wantedVersion[0]).$($wantedVersion[1]).$($wantedVersion[2]).$($wantedVersion[3])"
}

function GetReleasedVersion()
{
    param([string]$accountName, [string]$feedId, [string]$name)
    $releasedVersion=$null
    $packages=GetPackages $accountName $feedId
    $packages | % { 
        if($_.Name -eq $name) {
            #Write-Host "Found package!"
            $_.versions | % {
                $packageVersion=GetVersionFromVersionRange $_.Version
                if($releasedVersion -eq $null) {
                    $releasedVersion = $packageVersion
                    return;
                }
                if($releasedVersion[0] -gt $packageVersion[0]) {
                    return
                }
                if($releasedVersion[1] -gt $packageVersion[1]) {
                    return
                }
                if($releasedVersion[2] -gt $packageVersion[2]) {
                    return
                }
            }
        } 
    }
    if($releasedVersion -eq $null) {
        return "0.0.0.0"
    }
    return "$($releasedVersion[0]).$($releasedVersion[1]).$($releasedVersion[2])"
}

function Release
{
    param([string] $name, [string] $version)

    $match=[regex]::Match("$version", "(\d)+.(\d)+.(\d)+(-build(\d)+)*")
    if(-not $match.Success) 
    {
        Write-Host "$version is not valid"
        return
    }
    $version="$($match.captures.groups[1].Value).$($match.captures.groups[2].Value).$($match.captures.groups[3].Value)"

    # get latest version from the "prerelease" repo
    $versionToRelease=$null
    (GetPackages $prereleaseFeedId) | % {
        if($_.Name -eq $name) {
            Write-Host "Found package"
            $_.versions | % {
                if($_.isLatest) 
                {
                    if("$($_.Version)".StartsWith("$version-build")) {
                        Write-Host "Found version"
                        $versionToRelease=$_.Version
                    }
                }
            }
        }
    }
    if(-not $versionToRelease) {
        Write-Host "Could not find package $name in $prereleaseFeedId"
        return;
    }
    Write-Host "Releasing $name-$versionToRelease"
    
#    $packageeVersion=GetPackageVersion $prereleaseFeedId "TimeMachine.Impl.SqlServer" "1.1.4-build071"
#    foreach($dep in $packageeVersion.Dependencies) 
#    {
#        $depVersion=GetVersionFromVersionRange $dep.VersionRange
#        if($depVersion) 
#        {
#            Release $dep.PackageName $depVersion
#        }
#    }
}

function GetLatestVersion() 
{
    param([string] $nuget1, [string] $nuget2)
    if("$nuget1" -eq "") {
        return $nuget2
    }
    if("$nuget2" -eq "") {
        return $nuget1
    }
    $v1=([System.IO.FileInfo]$nuget1).Directory.Name
    $v2=([System.IO.FileInfo]$nuget2).Directory.Name
    #Write-Host "Comparing $v1 and $v2"
    if($v1 -gt $v2) {
        return $nuget1
    } else {
        return $nuget2
    }
}
