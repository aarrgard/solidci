
#
# find all the csproj files
#
function FindCsprojFiles() {
    param([System.IO.DirectoryInfo] $baseDir, [System.Collections.ArrayList] $csProjFiles)
	if($csProjFiles -eq $null) {
		$csProjFiles = New-Object System.Collections.ArrayList
	}
    #Write-Host $baseDir.FullName
    $csprojFile=$null
    $baseDir.GetFiles() | ForEach-Object {
        if($_.Name.ToLower().EndsWith(".csproj")) {
            $csprojFile = $_
        }
    }
    if("$csprojFile" -ne "") {
		if(-not (ExcludeCsprojFile $csprojFile)) {
			$dummy=$csProjFiles.Add($csprojFile)
			return $csProjFiles
		}
    }

    $baseDir.GetDirectories() | ForEach-Object {
        $dummy=FindCsprojFiles $_ $csProjFiles
    }
    return $csProjFiles
}


#
# returns true if supplied file should be excluded.
#
function ExcludeCsprojFile {
    param([System.IO.FileInfo]$csProjFile)
	$excludeFiles="$($env:CSPROJ_EXCLUDE)"
	if("$excludeFiles" -eq "") {
		return $false
	}
    $retval=$false
    $excludeFiles.Split(',') | ForEach-Object {
	    if("$_" -eq "") {
		    return
	    }
        $fileSuffix = $_.Replace('\', [System.IO.Path]::DirectorySeparatorChar).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        #Write-Host $csProjFile.FullName $fileSuffix ($csProjFile.FullName.EndsWith($fileSuffix))
        if($csProjFile.FullName.EndsWith($fileSuffix)) {
            $retval = $true
        }
    }
    Write-Host $retval
	return $retval
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
    if(-not $csProjFile.Exists) {
        throw "File not found $($csProjFile.FullName)"
    }
	[xml]$scProjXml=Get-Content $csProjFile.FullName
    Write-Host $scProjXml
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

