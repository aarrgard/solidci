. "$PSScriptRoot\nuget.ps1"
. "$PSScriptRoot\csproj.ps1"
. "$PSScriptRoot\replace.ps1"
. "$PSScriptRoot\assert.ps1"

#
# test package versions
#
AssertAreEqual (GetVersionFromVersionRange "1.2.3") (@(1,2,3,0))
AssertAreEqual (GetVersionFromVersionRange "1.2.3-master") (@(1,2,3,0))
AssertAreEqual (GetVersionFromVersionRange "1.2.3.build1") (@(1,2,3,1))
AssertAreEqual (GetVersionFromVersionRange "1.2.3.4-build1") (@(1,2,3,1))

AssertAreEqual (GetVersionFromVersionRange "2018.5.6") (@(2018,5,6,0))
AssertAreEqual (GetVersionFromVersionRange "feature-234-build1") (@(0,0,234,1))
AssertAreEqual (GetVersionFromVersionRange "feature-235.build23") (@(0,0,235,23))
AssertAreEqual (GetVersionFromVersionRange "xxx") $null

#
# test csproj file support
#
$csProjFiles=FindCsprojFiles "$PSScriptRoot\..\..\.."
AssertAreEqual 1 $csProjFiles.Count
AssertAreEqual "SolidCI.Azure" $(GetCsprojPackageName $csProjFiles[0])

$feed_authorization=$null
if($feed_pat -ne $null) {
	$feed_authorization="Basic $([System.Convert]::FromBase64String(":$feed_pat"))"
}
if($($env:SYSTEM_ACCESSTOKEN) -ne $null) {
	$feed_authorization="Bearer $($env:SYSTEM_ACCESSTOKEN)"
}
if($feed_authorization -eq $null) {
	throw "Cannot determine feed authorization. Please set the FEED_PAT environment variable"
}
Set-variable -Name "FEED_AUTHORIZATION" -Value $feed_authorization -Scope Global 
$FEED_AUTHORIZATION