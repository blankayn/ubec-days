$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "extracted\People.obj"
$outDir = Join-Path $PSScriptRoot "characters"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$characters = [ordered]@{
    "civilian_secretary" = @("character_secretary")
    "civilian_female_2" = @("Female Civilian 2")
    "civilian_black_suit" = @("Body.008 6", "Face.008 6")
    "civilian_casual_male" = @("Body.008 2", "Face.008 2")
}

$lines = Get-Content -Path $src -Encoding UTF8
$vertices = @()
$texcoords = @()
$normals = @()
$objects = [ordered]@{}

$currentName = ""
$currentFaces = @()

function Flush-Object {
    param([string]$Name)
    if ($Name -ne "" -and $currentFaces.Count -gt 0) {
        $objects[$Name] = @($currentFaces)
    }
}

foreach ($line in $lines) {
    if ($line.StartsWith("v ")) {
        $vertices += $line
    }
    elseif ($line.StartsWith("vt ")) {
        $texcoords += $line
    }
    elseif ($line.StartsWith("vn ")) {
        $normals += $line
    }
    elseif ($line.StartsWith("o ")) {
        Flush-Object $currentName
        $currentName = $line.Substring(2).Trim()
        $currentFaces = @()
    }
    elseif ($line.StartsWith("f ")) {
        if ($currentName -ne "") {
            $currentFaces += $line
        }
    }
}
Flush-Object $currentName

function Remap-IndexSet {
    param([int[]]$Indices)
    $map = @{}
    $ordered = $Indices | Sort-Object -Unique
    $newIndex = 1
    foreach ($idx in $ordered) {
        $map[$idx] = $newIndex
        $newIndex++
    }
    return @{
        map = $map
        ordered = $ordered
    }
}

function Write-CharacterObj {
    param(
        [string]$OutputName,
        [string[]]$ObjectNames
    )

    $faceLines = @()
    foreach ($objectName in $ObjectNames) {
        if (-not $objects.Contains($objectName)) {
            throw "Missing object '$objectName' in source OBJ"
        }
        $faceLines += $objects[$objectName]
    }

    $usedV = [System.Collections.Generic.HashSet[int]]::new()
    $usedVt = [System.Collections.Generic.HashSet[int]]::new()
    $usedVn = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($face in $faceLines) {
        $parts = $face.Substring(2).Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
        foreach ($part in $parts) {
            $indices = $part.Split("/")
            if ($indices[0] -ne "") { [void]$usedV.Add([int]$indices[0]) }
            if ($indices.Count -gt 1 -and $indices[1] -ne "") { [void]$usedVt.Add([int]$indices[1]) }
            if ($indices.Count -gt 2 -and $indices[2] -ne "") { [void]$usedVn.Add([int]$indices[2]) }
        }
    }

    $vData = Remap-IndexSet @($usedV)
    $vtData = Remap-IndexSet @($usedVt)
    $vnData = Remap-IndexSet @($usedVn)

    $out = @("# Split from People.obj for $OutputName", "o $OutputName")
    foreach ($idx in $vData.ordered) {
        $out += $vertices[$idx - 1]
    }
    foreach ($idx in $vtData.ordered) {
        $out += $texcoords[$idx - 1]
    }
    foreach ($idx in $vnData.ordered) {
        $out += $normals[$idx - 1]
    }

    foreach ($objectName in $ObjectNames) {
        $out += "g $objectName"
        $out += if ($objectName.StartsWith("Face")) { "usemtl face" } else { "usemtl body" }
        foreach ($face in $objects[$objectName]) {
            $parts = $face.Substring(2).Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
            $newParts = @()
            foreach ($part in $parts) {
                $indices = $part.Split("/")
                $v = $vData.map[[int]$indices[0]]
                if ($indices.Count -gt 2 -and $indices[1] -ne "" -and $indices[2] -ne "") {
                    $vt = $vtData.map[[int]$indices[1]]
                    $vn = $vnData.map[[int]$indices[2]]
                    $newParts += "$v/$vt/$vn"
                }
                elseif ($indices.Count -gt 1 -and $indices[1] -ne "") {
                    $vt = $vtData.map[[int]$indices[1]]
                    $newParts += "$v/$vt"
                }
                else {
                    $newParts += "$v"
                }
            }
            $out += "f $($newParts -join ' ')"
        }
    }

    $path = Join-Path $outDir "$OutputName.obj"
    $out | Set-Content -Path $path -Encoding UTF8
    Write-Host "Wrote $path"
}

foreach ($entry in $characters.GetEnumerator()) {
    Write-CharacterObj -OutputName $entry.Key -ObjectNames $entry.Value
}
