# Generate multi-size windows/runner/resources/app_icon.ico from assets/icon/app_icon.png.
#
# Why: flutter_launcher_icons only emits a single 256px entry; Windows shell
# downscales it at display time with low quality, causing heavy aliasing on
# 16/24/32/48px icons (explorer, taskbar, properties dialog). This script
# pre-generates every size with GDI+ HighQualityBicubic (progressive halving
# + TileFlipXY edge handling) and assembles a PNG-compressed multi-entry ICO.
#
# Usage: powershell.exe -ExecutionPolicy Bypass -File tools\make_multisize_ico.ps1
# Note: keep flutter_launcher_icons "windows.generate: false" in pubspec.yaml,
# otherwise a rerun of that tool overwrites this ICO with the single-size one.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $root 'assets\icon\app_icon.png'
$outPath = Join-Path $root 'windows\runner\resources\app_icon.ico'

function Resize-Step([System.Drawing.Image]$img, [int]$w) {
    $bmp = New-Object System.Drawing.Bitmap($w, $w, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $w)
    $g.DrawImage($img, $rect, 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    $g.Dispose(); $attr.Dispose()
    return $bmp
}

# Halve repeatedly until close to target, then do the final resize.
# Direct 1254 -> 16 in one bicubic pass loses too much detail.
function Resize-Progressive([System.Drawing.Image]$src, [int]$target) {
    $cur = $src; $own = $false
    while ([int]($cur.Width / 2) -gt $target) {
        $next = Resize-Step $cur ([int]($cur.Width / 2))
        if ($own) { $cur.Dispose() }
        $cur = $next; $own = $true
    }
    $final = Resize-Step $cur $target
    if ($own) { $cur.Dispose() }
    return $final
}

$src = [System.Drawing.Image]::FromFile($srcPath)
$sizes = @(256, 128, 64, 48, 32, 24, 16)
$blobs = @()
foreach ($s in $sizes) {
    $bmp = Resize-Progressive $src $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $blobs += , @{ Size = $s; Data = $ms.ToArray() }
    $ms.Dispose(); $bmp.Dispose()
    Write-Host ("generated {0}x{0}" -f $s)
}
$src.Dispose()

# ICO layout: ICONDIR(6B) + ICONDIRENTRY(16B)*N + image blobs.
$count = $blobs.Count
$offset = 6 + 16 * $count
$fs = [System.IO.File]::Create($outPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$count)
foreach ($b in $blobs) {
    $dim = if ($b.Size -ge 256) { [byte]0 } else { [byte]$b.Size }   # 0 means 256
    $bw.Write($dim); $bw.Write($dim)
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$b.Data.Length)
    $bw.Write([uint32]$offset)
    $offset += $b.Data.Length
}
foreach ($b in $blobs) { $bw.Write($b.Data) }
$bw.Dispose(); $fs.Dispose()
Write-Host ("written {0} ({1} bytes, {2} entries)" -f $outPath, (Get-Item $outPath).Length, $count)
