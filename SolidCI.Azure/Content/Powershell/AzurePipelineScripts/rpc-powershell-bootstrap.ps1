#
# Find all the csproj files and determine the versions of Contracts.Rpc used.
# Export the powershell folder from that location.
#
$nugetPackageLocation=Resolve-Path "~"
$nugetPackageLocation=Join-Path $nugetPackageLocation ".nuget"
$nugetPackageLocation=Join-Path $nugetPackageLocation "packages"

if(-not (Test-Path $nugetPackageLocation))
{
    throw "Cannot locate nuget packages @ $nugetPackageLocation"
}

$contractsRpcVersion=$null
Get-ChildItem -Path $PSScriptRoot -Name "*.csproj" -Recurse | ForEach-Object {
    $fileName=[System.IO.Path]::Combine($PSScriptRoot, $_)
    $packageReference=Select-Xml -Path $fileName -XPath "/Project/ItemGroup/PackageReference[@Include='Contracts.Rpc']"
    if($packageReference) {
        $contractsRpcVersion = $packageReference[0].Node.Attributes.GetNamedItem("Version").Value
    }
}

$contractsRpcNugetPackageLocation=Join-Path $nugetPackageLocation "contracts.rpc"
$contractsRpcNugetPackageLocation=Join-Path $contractsRpcNugetPackageLocation $contractsRpcVersion

if(-not (Test-Path $contractsRpcNugetPackageLocation))
{
    throw "Cannot locate rpc nuget package @ $contractsRpcNugetPackageLocation. Missing a nuget restore?"
}

$contractsRpcPowershellLocation=Join-Path $contractsRpcNugetPackageLocation "content"
$contractsRpcPowershellLocation=Join-Path $contractsRpcPowershellLocation "Content" 
$contractsRpcPowershellLocation=Join-Path $contractsRpcPowershellLocation "Powershell"

Write-Host "Using $contractsRpcPowershellLocation as location for rpcPowershellScripts variable"
Write-Output ("##vso[task.setvariable variable=rpcPowershellScripts;]$contractsRpcPowershellLocation")
