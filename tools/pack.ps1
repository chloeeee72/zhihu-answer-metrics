<#
.SYNOPSIS
    Packs extension/ into a store-submission zip at the repo root.

.DESCRIPTION
    The zip contains only what the browser loads: manifest.json, content.js and the four
    raster icons. Reviewer-facing material under demo/, store/ and tools/ is excluded so
    it cannot be mistaken for extension code.

    Node equivalent: node tools/pack.mjs

.EXAMPLE
    pwsh -File tools/pack.ps1
#>

$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$extDir = Join-Path $repoRoot 'extension'
$zip = Join-Path $repoRoot 'store-package.zip'

$include = @(
    'manifest.json',
    'content.js',
    'icons\icon16.png',
    'icons\icon32.png',
    'icons\icon48.png',
    'icons\icon128.png'
)

foreach ($rel in $include) {
    $full = Join-Path $extDir $rel
    if (-not (Test-Path -LiteralPath $full)) {
        throw "missing required file: extension/$rel"
    }
}

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("zhm-pack-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $staging | Out-Null

try {
    foreach ($rel in $include) {
        $dest = Join-Path $staging $rel
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -LiteralPath (Join-Path $extDir $rel) -Destination $dest
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $staging,
        $zip,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}

$size = (Get-Item -LiteralPath $zip).Length
Write-Output ("packed {0} ({1} bytes)" -f $zip, $size)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $archive.Entries | ForEach-Object { Write-Output ("  " + $_.FullName) }
}
finally {
    $archive.Dispose()
}
