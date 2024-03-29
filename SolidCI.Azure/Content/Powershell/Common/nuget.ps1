#
# setup feed authorization
#
function GetFeedAuthorization() {
    param([string] $uri)

    $feedAuthorization=""

    if("$feedAuthorization" -eq "") {
        if($($env:SYSTEM_ACCESSTOKEN) -ne $null) {
	        Write-Host "Using bearer authorization to access feeds - using system accesstoken"
	        $feedAuthorization="Bearer $($env:SYSTEM_ACCESSTOKEN)"
        }
    }

    if("$feedAuthorization" -eq "") {
        if("$($env:FEED_PAT)" -ne "") {
	         "$($env:FEED_PAT)".Split(";") | ForEach-Object {
                $parts=$_.Split("=")
                if($parts.Length -eq 2) {
                    #Write-Host "Checking if $uri starts with $($parts[0])"
                    if($uri.StartsWith($parts[0])) {
                        Write-Host "Using basic authorization to access feed - using token from FEED_PAT($($parts[0]))"
                   	    $feedAuthorization="Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($parts[1])")))"
                    }
                } else {
                    throw "Malformed FEED_PAT part:$_"
                }
            }
        }
    }

    return $feedAuthorization
}

$requestCache=@{}
function InvokeWebRequest()
{
    param([string] $uri)

    #
    # check if the request is cached
    #
    $cachedResponse = $requestCache[$uri];
    if($cachedResponse -ne $null) {
        Write-Host "Returning cached response for $uri"
        return $cachedResponse
    } else {
        Write-Host "Getting data from $uri ..."
        try { 
            $resp=Invoke-WebRequest -Uri $uri -UseBasicParsing
        } catch {
			if($_.Exception.Response.StatusCode -eq "Unauthorized") {
                Write-Host "Server requires authorization - resending with auth header."
				try { 
					$feedAuthorization=GetFeedAuthorization $uri
					$headers = @{ "Authorization" =  $feedAuthorization}
					$resp=Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing
				} catch {
					$resp = $_.Exception.Response
				}
			} else {
	            $resp = $_.Exception.Response
			}
        }

        #Write-Host "Got data:$($resp)"
	    $statusCode=$resp.StatusCode
	    $acceptedCodes=@(200,203)
	    if(-not $($acceptedCodes).Contains($statusCode)) {
		    throw "Status code not ok ($statusCode). Should be one of $acceptedCodes"
	    }

        $res=$resp.Content | ConvertFrom-Json
        $requestCache[$uri] = $res
        return $res
    }
}

function runProcess ($cmd, $params, $windowStyle=1) {
    Write-Host "runProcess $cmd $params"

    $pi = new-object System.Diagnostics.ProcessStartInfo
    $pi.FileName = $cmd
    $pi.Arguments = $params
    $pi.UseShellExecute = $False
    $pi.CreateNoWindow  = $True
    $pi.RedirectStandardError = $True
    $pi.RedirectStandardOutput = $True
    $pi.WindowStyle = $windowStyle; #1 = hidden, 2 =maximized, 3=minimized, 4=normal
    $p = [System.Diagnostics.Process]::Start($pi)
    $p.WaitForExit()
    $output = $p.StandardOutput.ReadToEnd()
    $exitcode = $p.ExitCode
    Write-Host "ExitCode:$exitcode->$output"
    if("$exitcode" -ne "0") {
        throw "command failed"
    }
    $p.Dispose()
    return $output
}

#
# invokes the nuget exe
#
function InvokeNugetExe()
{
    #Write-Host "$args"
    $exe="dotnet"
    #$exe = $env:NUGETEXETOOLPATH
	#if("$exe" -eq "") 
	#{
	#    throw "The NUGETEXETOOLPATH is not set."
	#}

    #Write-Host "Running: $exe $args"
    #$process = Start-Process -FilePath $exe -ArgumentList "sources" -NoNewWindow -PassThru -Wait
    #$exitCode = $process.ExitCode
    #$result = $process.StandardOutput.ReadToEnd()

    $result=runProcess $exe $args
    return $result
}


#
# Returns all the feed sources
#
function GetNugetSources()
{
    param()
    $sources=@{}

    $nugetConfig=$env:nugetConfigPath
    if("$nugetConfig" -ne "") {
        $configFile=[System.IO.FileInfo]::new($nugetConfig)
        if(!$configFile.Exists) {
            throw "File does not exist $($configFile.FullName)"
        }
        [xml]$configXml=Get-Content $configFile.FullName
        $configXml.SelectNodes("/configuration/packageSources/add") | ForEach-Object {
            $sourceName = $_.Attributes["key"].Value
            $source = $_.Attributes["value"].Value
            $sources[$sourceName] = $source
        }

        return $sources
    }

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
# returns the service url
#
function GetServiceUrl() 
{
    param([string] $serviceName, [string[]] $serviceTypes)
    $rootUrl = (GetNugetSources)[$serviceName]
    $res = InvokeWebRequest $rootUrl 
    $found=$false
    $res.resources | ForEach-Object {
        $resource = $_
        if(-not $found) {
            $serviceTypes | ForEach-Object {
                $serviceType = $_
                if($resource.'@type' -eq $serviceType) {
                    $found=$true
                    return $resource.'@id'
                }
            }
        }
    }
    if($found -ne $true) {
        throw "Cannot find any of the service types $serviceTypes"
    }
}

#
# returns the information about a package @ a source
#
function GetNugetPackageVersions()
{
    param([string[]] $sourceNames, [string] $name)

    $nugetSources=GetNugetSources
    if($sourceNames -eq $null) {
        $sourceNames=$nugetSources.Keys
    }

    $versions = @()
    $sourceNames | ForEach-Object {
        try {
            GetNugetPackageMetaData $_ $name | ForEach-Object {
                $versions += $_.version
            }
	    } catch {
            if("$($_)" -ne "Status code not ok (NotFound). Should be one of 200 203") {
    		    throw
            }
	    }
    }
    return $versions
}

#
# Returns the nuget package meta data.
#
function GetNugetPackageMetaData() {
    param([string[]] $sourceName, [string] $name)
    $registrationBaseUrl=GetServiceUrl $sourceName $("RegistrationsBaseUrl/3.6.0", "RegistrationsBaseUrl/3.4.0", "RegistrationsBaseUrl/3.0.0-rc", "RegistrationsBaseUrl/3.0.0-beta", "RegistrationsBaseUrl")
    $res = InvokeWebRequest "$registrationBaseUrl$($name.ToLowerInvariant())/index.json" 
    $res.items | ForEach-Object {
        $pageUrl = $_.'@id'
        if($pageUrl) 
        {
            $pageRes = InvokeWebRequest $pageUrl
        } else 
        {
            $pageRes = $res
        }
        $pageRes.items | ForEach-Object {
            $catalogEntry=$_.catalogEntry
            @{
                id=$catalogEntry.id;
                version=$catalogEntry.version;
                title=$catalogEntry.title;
                authors=$catalogEntry.authors;
                description=$catalogEntry.description;
                projectUrl=$catalogEntry.projectUrl;               
            }
        }
    }
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
    $released=$false
	GetNugetPackageVersions $sourceName $name | ForEach-Object {
		if($wantedVersion -eq $_) {
			$released = $true
		}
	}
	return $released
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
    else 
    {
        $semVersuffix = "-build"
    }
    $wantedVersion=GetVersionFromVersionRange $version
    if($wantedVersion -eq $null) {
        $released = "0.0.0.0"
        GetNugetPackageVersions $sourceNames $name | ForEach-Object {
            if(-not $_.Contains('-')) {
                if($released -lt $_) {
                    $released = $_
                }
            }
        }
        $wantedVersion=GetVersionFromVersionRange $released
        $wantedVersion[1] = $wantedVersion[1] + 1
    }
    $wantedVersion="$($wantedVersion[0]).$($wantedVersion[1]).$($wantedVersion[2])$semVersuffix"
    $versions=GetNugetPackageVersions $sourceNames $name
    $nextVersion=0
    $versions | ForEach-Object {
        #Write-Host "$_"
        $match=[regex]::Match($_, "$wantedVersion[^\d]*(\d+)")
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
    $match=[regex]::Match("$versionRange", "^(\d+)[.](\d+)[.](\d+)(?:.\d+)*[\.\-](?:[^\d]+)(\d+)")
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

