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

