Add-Type -AssemblyName System.Drawing

$FrameSize = 256
$Directions = 64
$Columns = 8
$Rows = 8
$Padding = 4

# Everything is resolved relative to THIS SCRIPT.
$EntityRoot = Join-Path $PSScriptRoot "graphics\entity"

$GunSource = Join-Path $EntityRoot "long-range-cannon-sprite.png"
$OutputFile = Join-Path $EntityRoot "long-range-cannon-sheet.png"

Write-Host "Source:"
Write-Host "  $GunSource"
Write-Host ""
Write-Host "Output:"
Write-Host "  $OutputFile"
Write-Host ""

if (-not (Test-Path $GunSource)) {
  throw "Cannot find cannon source: $GunSource"
}

# ------------------------------------------------------------
# Load high-resolution master sprite
# ------------------------------------------------------------

$source = [System.Drawing.Bitmap]::FromFile($GunSource)

try {

  Write-Host "Source size: $($source.Width)x$($source.Height)"

  # The source image was designed so its rotation axis is its
  # exact geometric centre.
  $sourceCentreX = $source.Width / 2.0
  $sourceCentreY = $source.Height / 2.0

  # Find the radius of the source image from its centre to a corner.
  # Scaling using this radius guarantees that after rotation the
  # sprite remains inside a 256x256 frame.
  $sourceRadius = [Math]::Sqrt(
    ($sourceCentreX * $sourceCentreX) +
    ($sourceCentreY * $sourceCentreY)
  )

  $destinationRadius = ($FrameSize / 2.0) - $Padding
  $scale = $destinationRadius / $sourceRadius

  $scaledWidth = [int][Math]::Round(
    $source.Width * $scale
  )

  $scaledHeight = [int][Math]::Round(
    $source.Height * $scale
  )

  Write-Host "Master sprite size: ${scaledWidth}x${scaledHeight}"
  Write-Host "Rotation centre: 128,128"
  Write-Host ""

  # ------------------------------------------------------------
  # Create ONE master 256x256 frame
  # ------------------------------------------------------------

  $master = New-Object System.Drawing.Bitmap(
    $FrameSize,
    $FrameSize,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
  )

  $g = [System.Drawing.Graphics]::FromImage($master)

  try {

    $g.Clear(
      [System.Drawing.Color]::Transparent
    )

    $g.CompositingMode =
    [System.Drawing.Drawing2D.CompositingMode]::SourceCopy

    $g.CompositingQuality =
    [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

    $g.InterpolationMode =
    [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $g.SmoothingMode =
    [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

    $g.PixelOffsetMode =
    [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # Centre the scaled source exactly in the 256x256 frame.
    $x = [int][Math]::Round(
      ($FrameSize - $scaledWidth) / 2.0
    )

    $y = [int][Math]::Round(
      ($FrameSize - $scaledHeight) / 2.0
    )

    $destination = New-Object System.Drawing.Rectangle(
      $x,
      $y,
      $scaledWidth,
      $scaledHeight
    )

    $g.DrawImage(
      $source,
      $destination,
      0,
      0,
      $source.Width,
      $source.Height,
      [System.Drawing.GraphicsUnit]::Pixel
    )
  }
  finally {
    $g.Dispose()
  }

  # ------------------------------------------------------------
  # Create 2048x2048 Factorio sprite sheet
  # ------------------------------------------------------------

  $sheetWidth = $Columns * $FrameSize
  $sheetHeight = $Rows * $FrameSize

  $sheet = New-Object System.Drawing.Bitmap(
    $sheetWidth,
    $sheetHeight,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
  )

  $sg = [System.Drawing.Graphics]::FromImage($sheet)

  try {

    $sg.Clear(
      [System.Drawing.Color]::Transparent
    )

    $sg.CompositingMode =
    [System.Drawing.Drawing2D.CompositingMode]::SourceCopy

    $sg.CompositingQuality =
    [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

    $sg.InterpolationMode =
    [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $sg.SmoothingMode =
    [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

    $sg.PixelOffsetMode =
    [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # --------------------------------------------------------
    # Generate all 64 directions from EXACTLY the same bitmap.
    # --------------------------------------------------------

    for ($direction = 0; $direction -lt $Directions; $direction++) {

      $column = $direction % $Columns
      $row = [int][Math]::Floor(
        $direction / $Columns
      )

      # 360 / 64 = 5.625 degrees
      $angle = $direction * 5.625

      # Exact centre of this 256x256 cell.
      $cellCentreX =
      ($column * $FrameSize) +
      ($FrameSize / 2)

      $cellCentreY =
      ($row * $FrameSize) +
      ($FrameSize / 2)

      $state = $sg.Save()

      try {

        # Put coordinate origin at centre of cell.
        $sg.TranslateTransform(
          $cellCentreX,
          $cellCentreY
        )

        # Rotate around the centre.
        $sg.RotateTransform(
          $angle
        )

        # Draw master so its (128,128) lies exactly
        # on the rotation point.
        $sg.DrawImageUnscaled(
          $master,
          - ($FrameSize / 2),
          - ($FrameSize / 2)
        )
      }
      finally {
        $sg.Restore($state)
      }
    }

    # --------------------------------------------------------
    # Save
    # --------------------------------------------------------

    $sheet.Save(
      $OutputFile,
      [System.Drawing.Imaging.ImageFormat]::Png
    )
  }
  finally {
    $sg.Dispose()
    $sheet.Dispose()
  }

  Write-Host "SUCCESS"
  Write-Host ""
  Write-Host "Generated:"
  Write-Host "  $OutputFile"
  Write-Host ""
  Write-Host "Sheet: 2048x2048"
  Write-Host "Cells: 8x8"
  Write-Host "Frame: 256x256"
  Write-Host "Directions: 64"
  Write-Host "Angle step: 5.625 degrees"
  Write-Host "Pivot: 128,128"

}
finally {

  if ($null -ne $master) {
    $master.Dispose()
  }

  $source.Dispose()
}