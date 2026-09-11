<#
.SYNOPSIS
    Renders the extension icon set from vector primitives plus a CJK glyph.

.DESCRIPTION
    Design brief: flat, one-glyph icon in Zhihu's blue, matching the restrained style of
    the site's own mark while staying clearly a third-party tool.

      tile  - rounded square, #056DE8, corner radius 23% of the side (iOS/Zhihu-like squircle)
      glyph - single white CJK character, optically centred, ~62% of the tile width
      ring  - optional thin white progress ring beside the glyph (reading-time hint)

    The glyph is drawn with a real system CJK font and downscaled from a large master
    bitmap with high-quality bicubic filtering, which keeps the strokes clean at 16px.
    Rasterizing with GDI+ instead of a headless browser is deliberate: it is deterministic
    on Windows and does not depend on a browser being installed.

    The equivalent SVG is written alongside the PNGs as an editable source, but the PNGs
    are the authoritative assets (font-based SVG text is not portable across renderers).

.EXAMPLE
    pwsh -File tools/render-icons.ps1
    pwsh -File tools/render-icons.ps1 -Glyph '时' -Ring
    pwsh -File tools/render-icons.ps1 -Glyph '字' -Design bars
#>

[CmdletBinding()]
param(
    [ValidateSet('glyph', 'bars')]
    [string]$Design = 'glyph',

    [string]$Glyph = '字',

    [switch]$Ring,

    [string]$Blue = '#056DE8',

    [string]$GlyphColor = '#FFFFFF',

    [string[]]$FontStack = @('Microsoft YaHei UI', 'Microsoft YaHei', 'Noto Sans SC', 'SimHei', 'SimSun'),

    # Raster sizes written to icons/ as icon<size>.png
    [int[]]$Sizes = @(300, 128, 48, 32, 16)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$iconDir = Join-Path $root 'icons'
[System.IO.Directory]::CreateDirectory($iconDir) | Out-Null

function ConvertFrom-HexColor {
    param([string]$Hex)
    $h = $Hex.TrimStart('#')
    if ($h.Length -ne 6) { throw "expected #RRGGBB, got '$Hex'" }
    return [System.Drawing.Color]::FromArgb(
        255,
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16)
    )
}

function Resolve-FontFamily {
    param([string[]]$Candidates)
    $installed = [System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name }
    foreach ($name in $Candidates) {
        if ($installed -contains $name) { return $name }
    }
    throw ("none of these fonts are installed: " + ($Candidates -join ', '))
}

function New-RoundedRectPath {
    param([single]$X, [single]$Y, [single]$W, [single]$H, [single]$Radius)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $p.AddArc($X, $Y, $d, $d, 180, 90)
    $p.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $p.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $p.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$blueColor = ConvertFrom-HexColor $Blue
$glyphColorValue = ConvertFrom-HexColor $GlyphColor
$fontName = Resolve-FontFamily -Candidates $FontStack
Write-Output "font: $fontName"

# --- master bitmap -----------------------------------------------------------
# Everything is drawn on a 1024px master, then downscaled. Drawing small directly would
# lose the glyph's stroke joins.
$master = 1024
$bmp = New-Object System.Drawing.Bitmap($master, $master)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

# Tile
$radius = [single]($master * 0.23)
$tilePath = New-RoundedRectPath -X 0 -Y 0 -W $master -H $master -Radius $radius
$tileBrush = New-Object System.Drawing.SolidBrush($blueColor)
$g.FillPath($tileBrush, $tilePath)

$glyphBrush = New-Object System.Drawing.SolidBrush($glyphColorValue)
$whitePen = New-Object System.Drawing.Pen($glyphColorValue, [single]($master * 0.032))
$whitePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$whitePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

if ($Design -eq 'glyph') {
    # Optical centring: GDI+ centres the em box, but CJK glyphs sit slightly high in it,
    # so the text rectangle is nudged down by ~1.5% of the tile.
    $fontSize = [single]($master * 0.62)
    $font = New-Object System.Drawing.Font($fontName, $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center

    if ($Ring) {
        # Glyph shifts left, ring occupies the right column.
        $textRect = New-Object System.Drawing.RectangleF(0, ($master * 0.015), ($master * 0.72), $master)
        $g.DrawString($Glyph, $font, $glyphBrush, $textRect, $fmt)

        $cx = [single]($master * 0.775)
        $cy = [single]($master * 0.5)
        $r = [single]($master * 0.135)
        $trackPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, $glyphColorValue), [single]($master * 0.058))
        $g.DrawEllipse($trackPen, ($cx - $r), ($cy - $r), ($r * 2), ($r * 2))

        $arcPen = New-Object System.Drawing.Pen($glyphColorValue, [single]($master * 0.058))
        $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($arcPen, ($cx - $r), ($cy - $r), ($r * 2), ($r * 2), -90, 260)
        $trackPen.Dispose(); $arcPen.Dispose()
    }
    else {
        $textRect = New-Object System.Drawing.RectangleF(0, ($master * 0.015), $master, $master)
        $g.DrawString($Glyph, $font, $glyphBrush, $textRect, $fmt)
    }
    $font.Dispose(); $fmt.Dispose()
}
else {
    # Ascending bars = text volume. Kept for side-by-side comparison.
    $barW = [single]($master * 0.145)
    $gap = [single]($master * 0.085)
    $left = [single]($master * 0.205)
    $bottom = [single]($master * 0.735)
    $heights = @(0.26, 0.40, 0.54)
    for ($i = 0; $i -lt 3; $i++) {
        $h = [single]($master * $heights[$i])
        $x = $left + $i * ($barW + $gap)
        $barPath = New-RoundedRectPath -X $x -Y ($bottom - $h) -W $barW -H $h -Radius ([single]($barW * 0.28))
        $g.FillPath($glyphBrush, $barPath)
        $barPath.Dispose()
    }
    $baselinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(215, $glyphColorValue), [single]($master * 0.036))
    $baselinePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $baselinePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($baselinePen, ($left - $master * 0.035), ($bottom + $master * 0.062), ($left + 3 * $barW + 2 * $gap + $master * 0.035), ($bottom + $master * 0.062))
    $baselinePen.Dispose()
}

$g.Dispose()

# --- downscale ---------------------------------------------------------------
foreach ($size in ($Sizes | Sort-Object -Descending)) {
    $out = New-Object System.Drawing.Bitmap($size, $size)
    $og = [System.Drawing.Graphics]::FromImage($out)
    $og.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $og.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $og.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $og.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $og.DrawImage($bmp, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)))
    $og.Dispose()

    $file = Join-Path $iconDir ("icon{0}.png" -f $size)
    $out.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
    Write-Output ("wrote {0} ({1}x{1})" -f $file, $size)
}

$bmp.Dispose()

# --- optional SVG source -----------------------------------------------------
# Reference only: text in SVG depends on the viewer's fonts, so the PNGs above win.
$svgPath = Join-Path $iconDir 'icon-source.svg'
$svgGlyph = if ($Design -eq 'glyph') {
    if ($Ring) {
        @"
  <text x="360" y="590" text-anchor="middle" font-size="620" font-weight="700" fill="$GlyphColor">$Glyph</text>
  <circle cx="790" cy="512" r="138" fill="none" stroke="$GlyphColor" stroke-opacity="0.31" stroke-width="59"/>
  <circle cx="790" cy="512" r="138" fill="none" stroke="$GlyphColor" stroke-width="59" stroke-linecap="round"
          stroke-dasharray="623 867" transform="rotate(-90 790 512)"/>
"@
    }
    else {
        @"
  <text x="512" y="728" text-anchor="middle" font-size="635" font-weight="700" fill="$GlyphColor">$Glyph</text>
"@
    }
}
else {
    @"
  <rect x="210" y="480" width="148" height="266" rx="41" fill="$GlyphColor"/>
  <rect x="445" y="419" width="148" height="327" rx="41" fill="$GlyphColor"/>
  <rect x="680" y="347" width="148" height="399" rx="41" fill="$GlyphColor"/>
  <rect x="174" y="790" width="676" height="37" rx="18" fill="$GlyphColor"/>
"@
}
$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect width="1024" height="1024" rx="235" ry="235" fill="$Blue"/>
$svgGlyph</svg>
"@
[System.IO.File]::WriteAllText($svgPath, $svg, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "wrote $svgPath (reference only)"
Write-Output ""
Write-Output ("design={0} glyph={1} ring={2} blue={3} font={4}" -f $Design, $Glyph, [bool]$Ring, $Blue, $fontName)
