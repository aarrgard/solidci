. "$PSScriptRoot\..\Common\nuget.ps1"
. "$PSScriptRoot\..\Common\csproj.ps1"
. "$PSScriptRoot\..\Common\replace.ps1"

$accountName=$env:ACCOUNTNAME
$buildnumber=$env:BUILD_BUILDNUMBER
$buildSourcesDirectory=$env:BUILD_SOURCESDIRECTORY
$buildSourceBranchName=$env:BUILD_SOURCEBRANCHNAME
$buildRepositoryName=$env:BUILD_REPOSITORY_NAME
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

    if("$($env:SYSTEM_ACCESSTOKEN)" -eq "") {
        


        $subscriptionId = "c8db6045-f06a-4d9a-99c4-45af85f0fe8a"
        #$rmAccount = Add-AzureRmAccount -SubscriptionId $subscriptionId
        $tenantId = (Get-AzureRmSubscription -SubscriptionId $subscriptionId).TenantId
        $tokenCache = (Get-AzureRmContext).TokenCache
        $cachedTokens = $tokenCache.ReadItems() `
            | where { $_.TenantId -eq $tenantId } `
            | Sort-Object -Property ExpiresOn -Descending
        $env:SYSTEM_ACCESSTOKEN = $cachedTokens[0].AccessToken
        $env:CSPROJ_1 = "Author:Andreas Arrgård"
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
# determine if this is a release
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

Write-Host "##vso[task.setvariable variable=FEED_ID;isOutput=true]$($feedId)"
Write-Host "Will publish to feed $($feedId)"


#
# emit vars
#
Write-Host "Defined variables:"
Write-Host "accountName:($accountName)"
Write-Host "buildnumber:($buildnumber)"
Write-Host "buildSourcesDirectory:($buildSourcesDirectory)"
Write-Host "nugetPackage:($nugetPackage)"
Write-Host "projectFolder:($projectFolder)"
Write-Host "buildRepositoryName:($buildRepositoryName)"
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
	$nextVersionNumber=GetNextVersionNumber $accountName $feedReleased $feedId $nugetPackage $buildSourceBranchName
	$nextNugetVersionNumber=GetVersionFromVersionRange $nextVersionNumber
	if("$($semVerPreRelease)" -eq "") 
	{ 
		$nextNugetVersionNumber=FormatString -patterArgs $nextNugetVersionNumber -pattern "{0}.{1}.{2}"
	} 
	else 
	{
		$nextNugetVersionNumber=FormatString -patterArgs $nextNugetVersionNumber -pattern "{0}.{1}.{2}-$($semVerPreRelease){3:000}"
	}

	#
	# Check if already released
	#
	Write-Host "Checking if $nugetPackage-$nextNugetVersionNumber is released."
	$released=IsReleased $accountName $feedReleased $nugetPackage $nextVersionNumber
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
    "[assembly: System.Reflection.AssemblyMetadata(""RepositoryName"", ""$buildRepositoryName"")]" | Out-File -FilePath $metadataFile -Append
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
            $colonIdx=$_.Value.IndexOf(':')
            if($colonIdx -gt -1) {
                $csprojProps[$_.Value.Substring(0, $colonIdx)] = $_.Value.Substring($colonIdx+1)
                $csprojProps
            }
        }
    }
    $csprojProps["Version"] = $nextNugetVersionNumber
    $csprojProps["AssemblyVersion"] = $nextVersionNumber
    $csprojProps["FileVersion"] = $nextVersionNumber
    WriteProjectProperties $csprojFile $csprojProps
}
