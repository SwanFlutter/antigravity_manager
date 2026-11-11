param(
  [string]$Out = 'C:\Users\SjjadKarimi\AppData\Local\Temp\screen.png',
  [int]$X = 0,
  [int]$Y = 0,
  [int]$W = 0,
  [int]$H = 0
)

Add-Type -AssemblyName System.Drawing
if ($W -le 0 -or $H -le 0) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $X = $b.X; $Y = $b.Y; $W = $b.Width; $H = $b.Height
}
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($X, $Y, 0, 0, $bmp.Size, [System.Drawing.CopyPixelOperation]::SourceCopy)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"Saved $Out ${W}x${H} at $X,$Y"
