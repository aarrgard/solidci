function SourceFile {
	param([string] $file)
    $file=$file.Replace('\',[System.IO.Path]::DirectorySeparatorChar).Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    $fileInfo = [System.IO.FileInfo]$file
	Write-Host "Sourcing file $($fileInfo.FullName)"
    if(-not $fileInfo.Exists) {
        throw "File does not exist($($fileInfo.FullName))."
    }
    return "$($fileInfo.FullName)"
}
. (SourceFile "$PSScriptRoot\..\Common\nuget.ps1")
. (SourceFile "$PSScriptRoot\..\Common\csproj.ps1")
. (SourceFile "$PSScriptRoot\..\Common\replace.ps1")

$accountName=$env:ACCOUNTNAME
$buildnumber=$env:BUILD_BUILDNUMBER
$buildSourcesDirectory=$env:BUILD_SOURCESDIRECTORY
$buildSourceBranchName=$env:BUILD_SOURCEBRANCHNAME
$buildRepositoryType="git"
$buildRepositoryUrl=$env:BUILD_REPOSITORY_URI 
$buildSourceVersion=$env:BUILD_SOURCEVERSION
$buildRepositoryUri=$env:BUILD_REPOSITORY_URI
$semVerPreRelease=$env:SEMVER_PRERELEASE
$projectFolder=$env:projectFolder
$feedReleased=$env:FEED_RELEASED
$feedPrerelease=$env:FEED_PRERELEASE
$system_teamfoundationserveruri=$env:SYSTEM_TEAMFOUNDATIONSERVERURI

Get-ChildItem Env:

if("$($env:TF_BUILD)" -ne "True") {
    #
    # Not running on a server
    #
    $accountName="andreas0539"
    $projectFolder="C:\Development\github\solidci\SolidCI.Azure"
    $buildnumber="20190310.2"
    $buildSourcesDirectory="C:\Development\github\solidci\"
    $buildSourceBranchName="master"
    $buildSourceVersion="09a3cdc04d68f16c7073c3f702a65ce20dec8103"
    $semVerPreRelease=""
    $env:nugetConfigPath="..\..\..\..\nuget.config"


    if("$($env:SYSTEM_ACCESSTOKEN)" -eq "") {
        $subscriptionId = "c8db6045-f06a-4d9a-99c4-45af85f0fe8a"
        #$rmAccount = Add-AzureRmAccount -SubscriptionId $subscriptionId
        $tenantId = (Get-AzSubscription -SubscriptionId $subscriptionId).TenantId
        $tokenCache = (Get-AzContext).TokenCache
        $cachedTokens = $tokenCache.ReadItems() `
            | where { $_.TenantId -eq $tenantId } `
            | Sort-Object -Property ExpiresOn -Descending
        $env:SYSTEM_ACCESSTOKEN = $cachedTokens[0].AccessToken
        $env:CSPROJ_1 = "Author:Andreas Arrg�rd"
    }
}

#
# use default values
#
if($feedReleased -eq $null) {
	$feedReleased = "Released"
}
if($feedPrerelease -eq $null) {
	$feedPrerelease = "Prerelease"
}
if($accountName -eq $null) {
	# match "https://dev.azure.com/andreas0539/"
	if($($system_teamfoundationserveruri -match "^.+//.+/([^/]+)/$") -eq $True) 
    {
	    $accountName = $Matches[1]
    }
}

#
# determine if this is a release - build
#
if("$($semVerPreRelease)" -eq "") {
    $semVerPreRelease = "build"
	$feedId = $feedPrerelease
} elseif("$($semVerPreRelease)" -eq "release") {
    $semVerPreRelease = ""
	$feedId = $feedReleased
} else {
	$feedId = $feedReleased
}

#
# setup push variables
#
$feedUrl=(GetNugetSources)[$feedId]
$feedType="internal"
if(!$feedUrl.StartsWith("https://pkgs.dev.azure.com/")) {
	$feedType="external"
}
Write-Host "##vso[task.setvariable variable=FEED_ID]$($feedId)"
Write-Host "##vso[task.setvariable variable=FEED_TYPE]$($feedType)"
Write-Host "Will publish to feed $feedId - $feedType - $feedUrl"


#
# emit vars
#
Write-Host "Defined variables:"
Write-Host "accountName:($accountName)"
Write-Host "buildnumber:($buildnumber)"
Write-Host "buildSourcesDirectory:($buildSourcesDirectory)"
Write-Host "nugetPackage:($nugetPackage)"
Write-Host "projectFolder:($projectFolder)"
Write-Host "buildRepositoryType:($buildRepositoryType)"
Write-Host "buildRepositoryUrl:($buildRepositoryUrl)"
Write-Host "buildSourceBranchName:($buildSourceBranchName)"
Write-Host "buildSourceVersion:($buildSourceVersion)"
Write-Host "feedPrerelease:($feedPrerelease)"
Write-Host "feedReleased:($feedReleased)"
Write-Host "feedId:($feedId)"
Write-Host "semVerPreRelease:($semVerPreRelease)"

#
# Locate all csproj files
#
$csProjFiles = FindCsprojFiles "$projectFolder"

#
# Process each csproj file separately
#
$csProjFiles | ForEach-Object {
    $csprojFile=[System.IO.FileInfo]$_
	Write-Host "Processing csproj file $($csprojFile.FullName)"

	#
	# determine name of nuget package for project
	#
	$nugetPackage=GetCsprojPackageName $csprojFile
	Write-Host "Using nuget package name $nugetPackage for project"

	#
	# Get the next version number to build
	# 
	Write-Host "GetNugetBuildVersion $feedId $nugetPackage $buildSourceBranchName $semVerPreRelease"
	$nextNugetVersionNumber=GetNugetBuildVersion $feedId $nugetPackage $buildSourceBranchName $semVerPreRelease
	Write-Host "GetVersionFromVersionRange $nextNugetVersionNumber"
	$nextVersionNumber=GetVersionFromVersionRange $nextNugetVersionNumber
	if("$semVerPreRelease" -eq "") 
	{ 
		$nextNugetVersionNumber=FormatString -patterArgs $nextVersionNumber -pattern "{0}.{1}.{2}"
	} 
	else 
	{
		$nextNugetVersionNumber=FormatString -patterArgs $nextVersionNumber -pattern "{0}.{1}.{2}-$($semVerPreRelease){3:000}"
	}
	$nextVersionNumber=FormatString -patterArgs $nextVersionNumber -pattern "{0}.{1}.{2}.{3}"

	#
	# Check if already released
	#
	Write-Host "Checking if $nugetPackage-$nextNugetVersionNumber is released."
	$released=IsNugetReleased $feedReleased $nugetPackage $nextVersionNumber
	if($released) {
		throw "Version $nextVersionNumber is already released"
	}

	Write-Host "Using $nextNugetVersionNumber as version for package $nugetPackage."

	#
	# create metadata file containing the source and version
	#
    $metadataFile="$($csprojFile.Directory.FullName)\BuildMetadata.cs"
    Write-Host "Creating file $metadataFile"
    "[assembly: System.Reflection.AssemblyMetadata(""NugetVersion"", ""$nextNugetVersionNumber"")]" | Out-File -FilePath $metadataFile
    "[assembly: System.Reflection.AssemblyMetadata(""RepositoryType"", ""$buildRepositoryType"")]" | Out-File -FilePath $metadataFile -Append
    "[assembly: System.Reflection.AssemblyMetadata(""RepositoryUrl"", ""$buildRepositoryUrl"")]" | Out-File -FilePath $metadataFile -Append
    "[assembly: System.Reflection.AssemblyMetadata(""SourceBranchName"", ""$buildSourceBranchName"")]" | Out-File -FilePath $metadataFile -Append
    "[assembly: System.Reflection.AssemblyMetadata(""SourceVersion"", ""$buildSourceVersion"")]" | Out-File -FilePath $metadataFile -Append
    "[assembly: System.Reflection.AssemblyMetadata(""VstsBuildNumber"", ""$buildnumber"")]" | Out-File -FilePath $metadataFile -Append

	#
    # Add csproj. data from environment
	# replace file & dll versions
	#
	$csprojProps = ReadProjectProperties $csprojFile
    Get-ChildItem Env: | ForEach-Object {
        if($_.Key.ToLower().StartsWith("csproj_")) {
			Write-Host "Handling csproj setting: $($_.Value)"
            $colonIdx=$_.Value.IndexOf(':')
            if($colonIdx -gt -1) {
                $csprojProps[$_.Value.Substring(0, $colonIdx)] = $_.Value.Substring($colonIdx+1)
            }
        }
    }
    $csprojProps["Version"] = $nextNugetVersionNumber
    $csprojProps["AssemblyVersion"] = $nextVersionNumber
    $csprojProps["FileVersion"] = $nextVersionNumber
    $csprojProps["RepositoryType"] = $buildRepositoryType
    $csprojProps["RepositoryUrl"] = $buildRepositoryUrl
    WriteProjectProperties $csprojFile $csprojProps
}
