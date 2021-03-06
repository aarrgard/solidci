$env:CSPROJ_EXCLUDE=""
if("$($env:SYSTEM_ACCESSTOKEN)" -eq "") {
        
    $subscriptionId = "c8db6045-f06a-4d9a-99c4-45af85f0fe8a"
    #$rmAccount = Add-AzureRmAccount -SubscriptionId $subscriptionId
    $tenantId = (Get-AzureRmSubscription -SubscriptionId $subscriptionId).TenantId
    $tokenCache = (Get-AzureRmContext).TokenCache
    $cachedTokens = $tokenCache.ReadItems() `
        | where { $_.TenantId -eq $tenantId } `
        | Sort-Object -Property ExpiresOn -Descending
    $env:SYSTEM_ACCESSTOKEN = $cachedTokens[0].AccessToken
    $env:CSPROJ_1 = "Author:Andreas Arrg�rd"
}
$env:SYSTEM_ACCESSTOKEN=""
$env:FEED_PAT="https://pkgs.dev.azure.com/andreas0539/_packaging=zxrj3ahccr3io34zmsk6w24364exdxfmqurbtefow3hdduwvmida;http://test=sesdfsd"
$env:nugetConfigPath="$PSScriptRoot\..\nuget.config"

. "$PSScriptRoot\..\SolidCI.Azure\Content\Powershell\Common\nuget.ps1"
. "$PSScriptRoot\..\SolidCI.Azure\Content\Powershell\Common\csproj.ps1"
. "$PSScriptRoot\..\SolidCI.Azure\Content\Powershell\Common\replace.ps1"
. "$PSScriptRoot\..\SolidCI.Azure\Content\Powershell\Common\assert.ps1"

#GetNugetSources
#$res=GetNugetPackageVersions2 "nuget.org" "Newtonsoft.Json"
#GetNugetBuildVersion nuget.org Newtonsoft.Json 1.0.0 build
#GetNugetBuildVersion Prerelease SolidCI.Azure 1.0.0 build
#GetNugetBuildVersion Prerelease SolidProxy.XUnitTests 1.0.0 build

#
# test package versions
#
AssertAreEqual (GetVersionFromVersionRange "1.2.3") (@(1,2,3,0))
AssertAreEqual (GetVersionFromVersionRange "1.2.3-master") (@(1,2,3,0))
AssertAreEqual (GetVersionFromVersionRange "1.2.3.build1") (@(1,2,3,1))
AssertAreEqual (GetVersionFromVersionRange "1.2.3-rc001") (@(1,2,3,1))
AssertAreEqual (GetVersionFromVersionRange "1.2.3.4-build1") (@(1,2,3,1))

AssertAreEqual (GetVersionFromVersionRange "2018.5.6") (@(2018,5,6,0))
AssertAreEqual (GetVersionFromVersionRange "feature-234-build1") (@(0,0,234,1))
AssertAreEqual (GetVersionFromVersionRange "feature-235.build23") (@(0,0,235,23))
AssertAreEqual (GetVersionFromVersionRange "xxx") $null

#
# test csproj file support
#
$csProjFiles=FindCsprojFiles "$PSScriptRoot\.."
AssertAreEqual 2 $csProjFiles.Count
AssertAreEqual "project" $(GetCsprojPackageName $csProjFiles[1])

$csprojProps = ReadProjectProperties $csProjFiles[1]
AssertAreEqual 8 $csprojProps.Count
$csprojProps["Version"] = "1.0.2"
WriteProjectProperties $csProjFiles[1] $csprojProps

$env:CSPROJ_EXCLUDE="sdasfd,/project.csproj"
AssertAreEqual 1 (FindCsprojFiles "$PSScriptRoot\..").Count
$env:CSPROJ_EXCLUDE=""

#
# nuget
#
#$versions=GetNugetPackageVersions "AndreasPrerelease" "SolidCI.Azure"
$versions=GetNugetPackageVersions "nuget.org" "Newtonsoft.Json"
AssertAreEqual 69 $versions.Length
$released=IsNugetReleased "nuget.org" "Newtonsoft.Json" "12.0.2-beta2"
AssertAreEqual $true $released
$released=IsNugetReleased "nuget.org" "Newtonsoft.Json" "12.0.2"
AssertAreEqual $true $released
$released=IsNugetReleased "nuget.org" "Newtonsoft.Json" "12.0.0"
AssertAreEqual $false $released
$buildVersion=GetNugetBuildVersion "nuget.org" "RestSharp" "106.2.0" "alpha"
AssertAreEqual "106.2.0-alpha061" $buildVersion


