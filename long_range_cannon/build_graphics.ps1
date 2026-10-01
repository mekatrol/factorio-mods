param(
  [Parameter(Mandatory = $true)][string]$GunSource,
  [Parameter(Mandatory = $true)][string]$BaseSource,
  [Parameter(Mandatory = $true)][string]$RoundSource
)

Add-Type -AssemblyName System.Drawing

$graphicsRoot = Join-Path $PSScriptRoot "graphics"
$entityRoot = Join-Path $graphicsRoot "entity"
$iconRoot = Join-Path $graphicsRoot "icons"
New-Item -ItemType Directory -Force -Path $entityRoot, $iconRoot | Out-Null

function New-FittedBitmap([string]$Path, [int]$Size, [int]$Padding) {
  $source = [System.Drawing.Bitmap]::FromFile($Path)
  try {
    $output = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($output)
    try {
      $graphics.Clear([System.Drawing.Color]::Transparent)
      $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
      $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $available = $Size - (2 * $Padding)
      $ratio = [Math]::Min($available / $source.Width, $available / $source.Height)
      $width = [int][Math]::Round($source.Width * $ratio)
      $height = [int][Math]::Round($source.Height * $ratio)
      $x = [int](($Size - $width) / 2)
      $y = [int](($Size - $height) / 2)
      $graphics.DrawImage($source, $x, $y, $width, $height)
    } finally {
      $graphics.Dispose()
    }
    return $output
  } finally {
    $source.Dispose()
  }
}

function New-PivotedCannonBitmap([string]$Path, [int]$Size, [int]$Padding) {
  $source = [System.Drawing.Bitmap]::FromFile($Path)
  try {
    # The generated source includes a long barrel and asymmetric transparent
    # padding. These coordinates identify the centre of the circular mounting
    # ring, which is the turret's actual rotation axis.
    $sourcePivotX = $source.Width * (626.0 / 1254.0)
    $sourcePivotY = $source.Height * (808.0 / 1254.0)

    # The most distant visible pixel is the muzzle, about 804 source pixels
    # from the pivot. Scale by that radius so every rotation fits in one frame.
    $sourceRadius = $source.Height * (804.0 / 1254.0)
    $scale = (($Size / 2) - $Padding) / $sourceRadius
    $width = [int][Math]::Round($source.Width * $scale)
    $height = [int][Math]::Round($source.Height * $scale)
    $x = [int][Math]::Round(($Size / 2) - ($sourcePivotX * $scale))
    $y = [int][Math]::Round(($Size / 2) - ($sourcePivotY * $scale))

    $output = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($output)
    try {
      $graphics.Clear([System.Drawing.Color]::Transparent)
      $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
      $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $graphics.DrawImage($source, $x, $y, $width, $height)
    } finally {
      $graphics.Dispose()
    }
    return $output
  } finally {
    $source.Dispose()
  }
}

$cannon = New-PivotedCannonBitmap $GunSource 256 5
$base = New-FittedBitmap $BaseSource 256 5
$sheet = New-Object System.Drawing.Bitmap(2048, 2048, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$sheetGraphics = [System.Drawing.Graphics]::FromImage($sheet)
try {
  $sheetGraphics.Clear([System.Drawing.Color]::Transparent)
  $sheetGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $sheetGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $sheetGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  for ($direction = 0; $direction -lt 64; $direction++) {
    $column = $direction % 8
    $row = [Math]::Floor($direction / 8)
    $state = $sheetGraphics.Save()
    $sheetGraphics.TranslateTransform(($column * 256) + 128, ($row * 256) + 128)
    $sheetGraphics.RotateTransform($direction * 5.625)
    $sheetGraphics.TranslateTransform(-128, -128)
    $sheetGraphics.DrawImageUnscaled($cannon, 0, 0)
    $sheetGraphics.Restore($state)
  }
  $sheet.Save((Join-Path $entityRoot "long-range-cannon-sheet.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $base.Save((Join-Path $entityRoot "long-range-cannon-base.png"), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $sheetGraphics.Dispose()
  $sheet.Dispose()
}

$cannonIcon = New-FittedBitmap $BaseSource 64 2
$roundIcon = New-FittedBitmap $RoundSource 64 3
try {
  $cannonIcon.Save((Join-Path $iconRoot "long-range-cannon.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $roundIcon.Save((Join-Path $iconRoot "long-range-cannon-round.png"), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $cannon.Dispose()
  $base.Dispose()
  $cannonIcon.Dispose()
  $roundIcon.Dispose()
}
