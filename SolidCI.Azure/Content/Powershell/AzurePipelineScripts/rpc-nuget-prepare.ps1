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
$releasebuild=$env:RELEASEBUILD
$projectFolder=$env:projectFolder
$releasedFeed=$env:releasedFeed
$prereleasedFeed=$env:prereleasedFeed
$system_teamfoundationserveruri=$env:SYSTEM_TEAMFOUNDATIONSERVERURI

Get-ChildItem Env:

if("$($env:SYSTEM_ACCESSTOKEN)" -eq "") {
    #
    # Not running on a server
    #
    $accountName="andreas0539"
    $projectFolder="C:\Development\devopsarrgard\ContractAPI\Projects\Contracts.Rpc\Contracts.Rpc"
    $buildnumber="20190310.2"
    $buildSourcesDirectory="C:\agent\_work\2\s"
    $buildSourceBranchName="master"
    $buildSourceVersion="09a3cdc04d68f16c7073c3f702a65ce20dec8103"
    $releasebuild="false"

    if("$system_accesstoken" -eq "") {

        $subscriptionId = ""
        #$rmAccount = Add-AzureRmAccount -SubscriptionId $subscriptionId
        $tenantId = (Get-AzureRmSubscription -SubscriptionId $subscriptionId).TenantId
        $tokenCache = (Get-AzureRmContext).TokenCache
        $cachedTokens = $tokenCache.ReadItems() `
            | where { $_.TenantId -eq $tenantId } `
            | Sort-Object -Property ExpiresOn -Descending
        $system_accesstoken = $cachedTokens[0].AccessToken

    }
}

#
# use default values
#
if($releasedFeed -eq $null) {
	$releasedFeed = "Released"
}
if($prereleasedFeed -eq $null) {
	$prereleasedFeed = "Prerelease"
}
if($accountName -eq $null) {
	# match "https://dev.azure.com/andreas0539/"
	if($($system_teamfoundationserveruri -match "^.+//.+/([^/]+)/$") -eq $True) 
    {
	    $accountName = $Matches[1]
    }
}

if($releasebuild -ieq "true") {
    $releasebuild = $true
} else {
    $releasebuild = $false
}

#
# emit vars
#
Write-Host "Defined variables:"
Write-Host "accountName:($accountName)"
Write-Host "prereleasedFeed:($prereleasedFeed)"
Write-Host "releasedFeed:($releasedFeed)"
Write-Host "buildnumber:($buildnumber)"
Write-Host "buildSourcesDirectory:($buildSourcesDirectory)"
Write-Host "nugetPackage:($nugetPackage)"
Write-Host "projectFolder:($projectFolder)"
Write-Host "buildRepositoryName:($buildRepositoryName)"
Write-Host "buildSourceBranchName:($buildSourceBranchName)"
Write-Host "buildSourceVersion:($buildSourceVersion)"
Write-Host "releasebuild:($releasebuild)"

Write-Host "System.AccessToken:$($system_accesstoken)"
Set-Variable -Name "system_accesstoken" -Value $system_accesstoken -Scope "global"

#
# Locate all csproj files
#
$csProjFiles = FindCsprojFiles "$projectFolder"

#
# determine feed to publish to
#
if($releasebuild) {
	$feedId = $releasedFeed
} else {
	$feedId = $prereleasedFeed
}
Write-Host "##vso[task.setvariable variable=feedId;isOutput=true]$($feedId)"
Write-Host "Will publish to feed $($feedId)"

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
	$nextVersionNumber=GetNextVersionNumber $accountName $releasedFeed $feedId $nugetPackage $buildSourceBranchName
	$nextNugetVersionNumber=GetVersionFromVersionRange $nextVersionNumber
	if($releasebuild) 
	{ 
		$nextNugetVersionNumber=FormatString -patterArgs $nextNugetVersionNumber -pattern "{0}.{1}.{2}"
	} 
	else 
	{
		if($buildSourceBranchName -ieq "master") 
		{
			$nextNugetVersionNumber=FormatString -patterArgs $nextNugetVersionNumber -pattern "{0}.{1}.{2}-master{3:000}"
		}
		else
		{
			$nextNugetVersionNumber=FormatString -patterArgs $nextNugetVersionNumber -pattern "{0}.{1}.{2}-build{3:000}"
		}
	}
	Write-Host "Checking if $nugetPackage-$nextNugetVersionNumber is released."

	#
	# Check if already released
	#
	$released=IsReleased $accountName $releasedFeed $nugetPackage $nextVersionNumber
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
	# replace file & dll versions - after adding the elements if missing
	#
	AddCsprojVersionsIfMissing $csprojFile
    ProcessFile $csprojFile.FullName "<Version>*</Version>" $nextNugetVersionNumber
    ProcessFile $csprojFile.FullName "<AssemblyVersion>*</AssemblyVersion>" $nextVersionNumber
    ProcessFile $csprojFile.FullName "<FileVersion>*</FileVersion>" $nextVersionNumber
}
