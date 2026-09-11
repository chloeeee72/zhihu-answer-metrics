<#
.SYNOPSIS
    Builds the 1280x800 store listing screenshot from a raw Zhihu page capture.

.DESCRIPTION
    Edge lists 640x480 or 1280x800 for screenshots; Chrome lists 640x400 or 1280x800.
    1280x800 satisfies both. A raw page capture at that size leaves the injected stats bar
    too small to read, so this composes one image from two crops of the same capture:

      top    - the stats bar, magnified until the counters are legible
      bottom - the answer header plus the first line of body text, moderate zoom, so the
               bar is shown in context

    The stats bar is located automatically: its background is a wide run of #f5f5f5 with a
    #056DE8 accent on the left edge, which is stable across captures and screen scales.

.EXAMPLE
    pwsh -File extension/tools/make-screenshot.ps1 -In screenshot.png
#>

[CmdletBinding()]
param(
    [string]$In = 'extension/store/screenshots/source-raw.png',

    [string]$Out = 'extension/store/screenshot-1280x800.png',

    [int]$CanvasWidth = 1280,

    [int]$CanvasHeight = 800,

    # Extra margin around the auto-detected stats bar, in source pixels.
    [int]$BarPadX = 14,

    [int]$BarPadY = 12,

    # Cross-check: the bar's left edge must fall in this x window, otherwise the detection
    # grabbed something else and the script fails loudly instead of shipping a bad image.
    [int]$ExpectBarLeftMin = 300,

    [int]$ExpectBarLeftMax = 900
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$inPath = if ([System.IO.Path]::IsPathRooted($In)) { $In } else { Join-Path $repoRoot $In }
$outPath = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $repoRoot $Out }
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $outPath)) | Out-Null

$INK = [System.Drawing.Color]::FromArgb(255, 18, 18, 18)
$GREY = [System.Drawing.Color]::FromArgb(255, 110, 110, 110)
$LINE = [System.Drawing.Color]::FromArgb(255, 224, 224, 224)

$fontFamily = 'Microsoft YaHei UI'
if (([System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name }) -notcontains $fontFamily) {
    $fontFamily = 'Microsoft YaHei'
}
function New-Font {
    param([single]$Size, [System.Drawing.FontStyle]$Style)
    New-Object System.Drawing.Font($fontFamily, $Size, $Style, [System.Drawing.GraphicsUnit]::Pixel)
}

$source = [System.Drawing.Image]::FromFile($inPath)
$src = New-Object System.Drawing.Bitmap($source)

# --- locate the stats bar ----------------------------------------------------
function Test-AccentBlue {
    param([System.Drawing.Color]$C)
    # The bar's left border is #056DE8. The page background is #f4f6f9, which is far
    # lighter, so this test separates the two cleanly.
    return ([Math]::Abs($C.R - 5) -lt 26 -and [Math]::Abs($C.G - 109) -lt 30 -and [Math]::Abs($C.B - 232) -lt 26)
}

function Test-BarBackground {
    param([System.Drawing.Color]$C)
    # #f5f5f5, the bar's fill. Kept tight so the almost-white page background is rejected.
    return ($C.R -ge 242 -and $C.R -le 249 -and [Math]::Abs($C.R - $C.G) -le 3 -and [Math]::Abs($C.G - $C.B) -le 4)
}

$barRows = @()
for ($y = 0; $y -lt $src.Height; $y++) {
    # Find a short blue run: the bar's left border.
    $accentStart = -1; $accentRun = 0
    for ($x = 0; $x -lt $src.Width; $x++) {
        if (Test-AccentBlue $src.GetPixel($x, $y)) {
            if ($accentRun -eq 0) { $accentStart = $x }
            $accentRun++
        }
        elseif ($accentRun -gt 0) {
            if ($accentRun -ge 2 -and $accentRun -le 10) { break }
            $accentRun = 0; $accentStart = -1
        }
    }
    if ($accentRun -lt 2 -or $accentRun -gt 10) { continue }

    # Immediately right of the accent there must be a long run of the bar's #f5f5f5 fill.
    # Anything else with blue next to it (buttons, links, logos) fails here.
    $probeStart = $accentStart + $accentRun
    $run = 0
    for ($x = $probeStart; $x -lt [Math]::Min($probeStart + 400, $src.Width); $x++) {
        if (Test-BarBackground $src.GetPixel($x, $y)) { $run++ } else { break }
    }
    if ($run -lt 300) { continue }

    # Extend the run to the bar's right edge for cropping.
    $total = $run
    for ($x = $probeStart + $run; $x -lt $src.Width; $x++) {
        if (Test-BarBackground $src.GetPixel($x, $y)) { $total++ }
        elseif ($total -ge 300) { break }
    }
    if ($total -ge 300) {
        $barRows += [pscustomobject]@{ Y = $y; Left = $accentStart; X = $probeStart; W = $total }
    }
}

if ($barRows.Count -lt 8) {
    throw "could not locate the stats bar in $inPath (found $($barRows.Count) matching rows)"
}

$barTop = ($barRows | Measure-Object -Property Y -Minimum).Minimum
$barBottom = ($barRows | Measure-Object -Property Y -Maximum).Maximum
$barLeft = ($barRows | Measure-Object -Property Left -Minimum).Minimum
$barRight = ($barRows | ForEach-Object { $_.X + $_.W - 1 } | Measure-Object -Maximum).Maximum

if ($barLeft -lt $ExpectBarLeftMin -or $barLeft -gt $ExpectBarLeftMax) {
    throw "stats bar left edge detected at x=$barLeft, outside the expected $ExpectBarLeftMin..$ExpectBarLeftMax window; refusing to compose"
}

Write-Output ("detected stats bar: x {0}..{1}, y {2}..{3}" -f $barLeft, $barRight, $barTop, $barBottom)

# --- crop rectangles ---------------------------------------------------------
# Bar strip: start a little left of the bar so the accent is inside the frame, but stop
# well before the bar's right edge - the fill stretches far past the last counter, and
# cropping to the full fill would waste the magnification budget on empty pixels.
$barCropX = [Math]::Max(0, $barLeft - $BarPadX)
$barCropY = [Math]::Max(0, $barTop - $BarPadY)
$barCropW = [Math]::Min($src.Width - $barCropX, 660)
$barCropH = ($barBottom - $barTop) + $BarPadY * 2 + 1

# Context: answer author row down through the first line of body text. Anchored to the
# detected bar so it tracks the bar instead of hard-coded pixels. Narrower than the bar
# crop so the moderate zoom is not wasted on the page background to the left.
$ctxCropX = [Math]::Max(0, $barLeft - 60)
$ctxCropY = [Math]::Max(0, $barTop - 190)
$ctxCropW = [Math]::Min(760, $src.Width - $ctxCropX)
$ctxCropH = [Math]::Min($src.Height - $ctxCropY, 250)

if ($ctxCropY + $ctxCropH -le $barBottom) {
    $ctxCropH = ($barBottom - $ctxCropY) + 60
}

# --- compose -----------------------------------------------------------------
$canvas = New-Object System.Drawing.Bitmap($CanvasWidth, $CanvasHeight)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.Clear([System.Drawing.Color]::White)

$margin = 48
$contentWidth = $CanvasWidth - $margin * 2
$inkBrush = New-Object System.Drawing.SolidBrush($INK)
$greyBrush = New-Object System.Drawing.SolidBrush($GREY)
$linePen = New-Object System.Drawing.Pen($LINE, 1)

# Tier 1: magnified bar, pinned near the top, scaled to fill the content width but capped
# so a very narrow bar crop cannot push the second figure off the canvas.
$maxBarH = 220
$barScale = [Math]::Min($contentWidth / $barCropW, $maxBarH / $barCropH)
$barW = [int]($barCropW * $barScale)
$barH = [int]($barCropH * $barScale)
$barX = $margin + [int](($contentWidth - $barW) / 2)
$barY = 44
$g.DrawImage($src,
    (New-Object System.Drawing.Rectangle($barX, $barY, $barW, $barH)),
    (New-Object System.Drawing.Rectangle($barCropX, $barCropY, [int]$barCropW, [int]$barCropH)),
    [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawRectangle($linePen, $barX, $barY, $barW, $barH)

# Label inside the figure's top-left corner so it costs no vertical space.
$label = '统计栏（放大）'
$labelFont = New-Font 17 ([System.Drawing.FontStyle]::Bold)
$labelSize = $g.MeasureString($label, $labelFont)
$g.FillRectangle([System.Drawing.Brushes]::White, $barX, $barY, ($labelSize.Width + 16), ($labelSize.Height + 4))
$g.DrawString($label, $labelFont, $inkBrush, ($barX + 8), ($barY + 2))

# Tier 2: context crop, filling the height left between tier 1 and the footer.
$ctxY = $barY + $barH + 52
$ctxBottom = $CanvasHeight - 74
$availH = $ctxBottom - $ctxY
$ctxScale = [Math]::Min($contentWidth / $ctxCropW, $availH / $ctxCropH)
$ctxW = [int]($ctxCropW * $ctxScale)
$ctxH = [int]($ctxCropH * $ctxScale)
$ctxX = $margin + [int](($contentWidth - $ctxW) / 2)

$g.DrawString('页面中实际位置', (New-Font 17 ([System.Drawing.FontStyle]::Bold)), $inkBrush, $ctxX, ($ctxY - 26))
$g.DrawImage($src,
    (New-Object System.Drawing.Rectangle($ctxX, $ctxY, $ctxW, $ctxH)),
    (New-Object System.Drawing.Rectangle($ctxCropX, $ctxCropY, [int]$ctxCropW, [int]$ctxCropH)),
    [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawRectangle($linePen, $ctxX, $ctxY, $ctxW, $ctxH)

# --- hide the mouse cursor ---------------------------------------------------
# Screen captures often include the pointer as a small dark arrow on a light background.
# It adds nothing to a store listing, so look for it inside the context crop and paint it
# out with the page background colour. Detection is deliberately narrow: a compact cluster
# of very dark pixels whose bounding box is small and roughly cursor-shaped.
$patched = 0
$scanY0 = [int]$ctxCropY + 8
$scanY1 = [int]($ctxCropY + $ctxCropH) - 8
$scanX0 = [int]$ctxCropX + 300          # skip the avatar / author column on the left
$scanX1 = [int]($ctxCropX + $ctxCropW) - 8

for ($y = $scanY0; $y -lt $scanY1; $y++) {
    for ($x = $scanX0; $x -lt $scanX1; $x++) {
        $p = $src.GetPixel($x, $y)
        if ($p.R -lt 90 -and $p.G -lt 90 -and $p.B -lt 90) {
            # Measure the dark cluster around this seed.
            $minX = $x; $maxX = $x; $minY = $y; $maxY = $y; $count = 0
            for ($yy = $y; $yy -lt [Math]::Min($y + 40, $scanY1); $yy++) {
                for ($xx = [Math]::Max($scanX0, $x - 4); $xx -lt [Math]::Min($x + 30, $scanX1); $xx++) {
                    $q = $src.GetPixel($xx, $yy)
                    if ($q.R -lt 110 -and $q.G -lt 110 -and $q.B -lt 110) {
                        $count++
                        if ($xx -lt $minX) { $minX = $xx }
                        if ($xx -gt $maxX) { $maxX = $xx }
                        if ($yy -lt $minY) { $minY = $yy }
                        if ($yy -gt $maxY) { $maxY = $yy }
                    }
                }
            }
            $bw = $maxX - $minX + 1
            $bh = $maxY - $minY + 1
            # Cursor: small, taller than wide, dense, and not a text line (text is wider
            # than tall and comes in long runs).
            if ($count -ge 30 -and $bw -le 32 -and $bh -le 40 -and $bh -gt $bw -and $count -ge ($bw * $bh * 0.25)) {
                $pad = 3
                $fill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
                $g.FillRectangle($fill, ($minX - $pad), ($minY - $pad), ($bw + $pad * 2 * 2), ($bh + $pad * 2))
                $fill.Dispose()
                $patched++
                Write-Output ("  patched cursor at {0},{1} ({2}x{3})" -f $minX, $minY, $bw, $bh)
                $y = $maxY
                break
            }
        }
    }
}
if ($patched -eq 0) { Write-Output '  no mouse cursor found in the context crop' }

# Footer rule + one-line summary.
$footY = $CanvasHeight - 52
$g.DrawLine($linePen, $margin, $footY, ($CanvasWidth - $margin), $footY)
$footFont = New-Font 16 ([System.Drawing.FontStyle]::Regular)
$g.DrawString('汉字 / 英文单词 / 数字计数  ·  总字数  ·  预计阅读时间  ·  零权限、零请求、不收集数据', $footFont, $greyBrush, $margin, ($footY + 14))
$right = '非官方第三方扩展'
$g.DrawString($right, $footFont, $greyBrush, ($CanvasWidth - $margin - $g.MeasureString($right, $footFont).Width), ($footY + 14))

$canvas.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $canvas.Dispose(); $src.Dispose(); $source.Dispose()

$info = Get-Item -LiteralPath $outPath
Write-Output ("wrote {0}" -f $outPath)
Write-Output ("  {0}x{1}  {2} bytes" -f $CanvasWidth, $CanvasHeight, $info.Length)
Write-Output ("  bar  source {0},{1} {2}x{3}  ->  x{4:N2}  {5}x{6} at {7},{8}" -f $barCropX, $barCropY, [int]$barCropW, [int]$barCropH, $barScale, $barW, $barH, $barX, $barY)
Write-Output ("  ctx  source {0},{1} {2}x{3}  ->  x{4:N2}  {5}x{6} at {7},{8}" -f $ctxCropX, $ctxCropY, [int]$ctxCropW, [int]$ctxCropH, $ctxScale, $ctxW, $ctxH, $ctxX, $ctxY)
Write-Output ("  tier2 bottom edge: {0} (footer rule at {1})" -f ($ctxY + $ctxH), $footY)
