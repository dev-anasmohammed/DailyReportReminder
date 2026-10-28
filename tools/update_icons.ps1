# Regenerate desktop icon assets from the supplied Flaticon PNG on Windows.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$source = [System.Drawing.Bitmap]::new((Join-Path $root 'assets/app_icon.png'))
function Render-Png([int]$size, [bool]$whiteBackground) {
  $bitmap = [System.Drawing.Bitmap]::new($size,$size)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear($(if($whiteBackground){[System.Drawing.Color]::White}else{[System.Drawing.Color]::Transparent}))
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source,0,0,$size,$size)
    $stream = [System.IO.MemoryStream]::new()
    try {$bitmap.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png);return ,$stream.ToArray()}
    finally {$stream.Dispose()}
  } finally {$graphics.Dispose();$bitmap.Dispose()}
}
try {
  foreach($size in @(16,32,64,128,256,512,1024)) {
    [System.IO.File]::WriteAllBytes((Join-Path $root "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png"),(Render-Png $size $true))
  }
  [System.IO.File]::WriteAllBytes((Join-Path $root 'assets/tray.png'),(Render-Png 32 $false))
  $sizes = @(16,24,32,48,64,128,256)
  $images = [System.Collections.Generic.List[byte[]]]::new()
  foreach($size in $sizes){$images.Add((Render-Png $size $true))}
  $stream = [System.IO.MemoryStream]::new()
  $writer = [System.IO.BinaryWriter]::new($stream)
  try {
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$sizes.Length)
    $offset = 6 + 16 * $sizes.Length
    for($i=0;$i -lt $sizes.Length;$i++){
      $dimension = if($sizes[$i] -eq 256){0}else{$sizes[$i]}
      $writer.Write([byte]$dimension);$writer.Write([byte]$dimension)
      $writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32)
      $writer.Write([uint32]$images[$i].Length);$writer.Write([uint32]$offset)
      $offset += $images[$i].Length
    }
    foreach($bytes in $images){$writer.Write($bytes)}
    $writer.Flush()
    [System.IO.File]::WriteAllBytes((Join-Path $root 'windows/runner/resources/app_icon.ico'),$stream.ToArray())
    [System.IO.File]::WriteAllBytes((Join-Path $root 'assets/tray.ico'),$stream.ToArray())
  } finally {$writer.Dispose();$stream.Dispose()}
} finally {$source.Dispose()}
