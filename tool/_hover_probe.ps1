param(
  [Parameter(Mandatory=$true)][string]$Xs,
  [Parameter(Mandatory=$true)][string]$Ys,
  [string]$Out = 'C:\Users\SjjadKarimi\AppData\Local\Temp\hover_probe.txt'
)

$XArr = $Xs.Split(',') | ForEach-Object { [int]$_ }
$YArr = $Ys.Split(',') | ForEach-Object { [int]$_ }

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;

public class Win2 {
  [DllImport("user32.dll") SetLastError=true)]
  public static extern bool SetCursorPos(int X, int Y);
}
'@

Add-Type -AssemblyName System.Drawing

$originX = 0
$originY = 23
$neutralX = 6
$neutralY = 6
$half = 24

function Snap([int]$cx, [int]$cy) {
  $size = $half * 2
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(($originX + $cx - $half), ($originY + $cy - $half), 0, 0, (New-Object System.Drawing.Size $size, $size))
  $sum = 0
  for ($ix = 0; $ix -lt $size; $ix++) {
    for ($iy = 0; $iy -lt $size; $iy++) {
      $c = $bmp.GetPixel($ix, $iy)
      $sum += $c.R + $c.G + $c.B
    }
  }
  $g.Dispose()
  $bmp.Dispose()
  return ($sum / ($size * $size * 3))
}

[Win2]::SetCursorPos($originX + $neutralX, $originY + $neutralY) | Out-Null
Start-Sleep -Milliseconds 400

$lines = foreach ($y in $YArr) {
  foreach ($x in $XArr) {
    [Win2]::SetCursorPos($originX + $neutralX, $originY + $neutralY) | Out-Null
    Start-Sleep -Milliseconds 260
    $before = Snap $x $y
    [Win2]::SetCursorPos($originX + $x, $originY + $y) | Out-Null
    Start-Sleep -Milliseconds 300
    $after = Snap $x $y
    $delta = [math]::Round($after - $before, 1)
    "{0} {1} delta={2} (before={3} after={4})" -f $x, $y, $delta, [math]::Round($before,1), [math]::Round($after,1)
  }
}
$lines | Set-Content -Path $Out -Encoding UTF8
$lines
