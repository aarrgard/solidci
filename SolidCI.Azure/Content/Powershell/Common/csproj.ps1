
#
# find all the csproj files
#
function FindCsprojFiles() {
    param([System.IO.DirectoryInfo] $baseDir, [System.Collections.ArrayList] $csProjFiles)
	if($csProjFiles -eq $null) {
		$csProjFiles = New-Object System.Collections.ArrayList
	}

    $csprojFile=$null
    $baseDir.GetFiles() | ForEach-Object {
        if($_.Name.ToLower().EndsWith(".csproj")) {
            $csprojFile = $_
        }
    }
    if("$csprojFile" -ne "") {
        $dummy=$csProjFiles.Add($csprojFile)
        return $csProjFiles
    }

    $baseDir.GetDirectories() | ForEach-Object {
        $dummy=FindCsprojFiles $_ $csProjFiles
    }
    return $csProjFiles
}

#
# Returns the package name for supplied csproj file.
#
function GetCsprojPackageName() {
    param([System.IO.FileInfo]$csProjFile)
	return [io.path]::GetFileNameWithoutExtension($csProjFile.Name)
}

#
# Adds the version elements to the csproj file if they are missing.
#
function AddCsprojVersionsIfMissing() {
    param([System.IO.FileInfo]$csProjFile)

	[xml]$scProjXml=Get-Content $csProjFile.FullName
	$propertyGroup = Select-Xml -Xml $scProjXml -XPath "/Project/PropertyGroup"

	$versionNode = Select-Xml -Xml $scProjXml -XPath "/Project/PropertyGroup/Version"
    if(-not $versionNode) {
        $versionNode = $scProjXml.CreateElement("Version")
        $versionNode.InnerText = "0.0.0"
        $dummy=$propertyGroup.Node.AppendChild($versionNode)
    }

	$versionNode = Select-Xml -Xml $scProjXml -XPath "/Project/PropertyGroup/AssemblyVersion"
    if(-not $versionNode) {
        $versionNode = $scProjXml.CreateElement("AssemblyVersion")
        $versionNode.InnerText = "0.0.0.0"
        $dummy=$propertyGroup.Node.AppendChild($versionNode)
    }

	$versionNode = Select-Xml -Xml $scProjXml -XPath "/Project/PropertyGroup/FileVersion"
    if(-not $versionNode) {
        $versionNode = $scProjXml.CreateElement("FileVersion")
        $versionNode.InnerText = "0.0.0"
        $dummy=$propertyGroup.Node.AppendChild($versionNode)
    }
    
    $scProjXml.Save($csProjFile.FullName)
}


