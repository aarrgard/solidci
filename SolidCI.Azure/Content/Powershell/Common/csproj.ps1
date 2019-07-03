
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
# Reads all the project properties
#
function ReadProjectProperties() {
    param([System.IO.FileInfo]$csProjFile)
	[xml]$scProjXml=Get-Content $csProjFile.FullName
    $props = @{}
	$propertyGroup = Select-Xml -Xml $scProjXml -XPath "/Project/PropertyGroup" | ForEach-Object {
        $_.Node.ChildNodes | ForEach-Object {
            $props[$_.Name] = $_.InnerXml
        }
    }
    
    return $props
}

#
# Updates/adds the supplied properties to the specified project
#
function WriteProjectProperties() {
    param([System.IO.FileInfo]$csProjFile, [Hashtable] $props)

	[xml]$scProjXml=Get-Content $csProjFile.FullName
	$propertyGroup = Select-Xml -Xml $scProjXml -XPath "/Project/PropertyGroup"

    $props.Keys | ForEach-Object {
        if($_.StartsWith("#")) {
            return
        }
	    $node = Select-Xml -Xml $scProjXml -XPath "/Project/PropertyGroup/$_"
        if(-not $node) {
            $node = $scProjXml.CreateElement($_)
            $node.InnerText = $props[$_]
            $dummy = $propertyGroup.Node.AppendChild($node)
        } elseif($Node.GetType().FullName -eq "Microsoft.PowerShell.Commands.SelectXmlInfo") {
            $node = $node.Node
        }
        $node.InnerText = $props[$_]
    }

    $scProjXml.Save($csProjFile.FullName)
}

