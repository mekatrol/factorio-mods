param(
    [string]$FactorioData = "C:\Program Files (x86)\Steam\steamapps\common\Factorio\data"
)

Add-Type -AssemblyName System.Drawing

$modRoot = Split-Path -Parent $PSScriptRoot
$sources = @(
    @{
        Input = Join-Path $FactorioData "base\graphics\entity\logistic-chest\requester-chest.png"
        Output = Join-Path $modRoot "graphics\entity\orange-requester-chest.png"
    },
    @{
        Input = Join-Path $FactorioData "base\graphics\icons\requester-chest.png"
        Output = Join-Path $modRoot "graphics\icons\orange-requester-chest.png"
    }
)

function Convert-BlueToOrange([System.Drawing.Color]$color) {
    if ($color.A -eq 0) { return $color }

    $hue = $color.GetHue()
    $saturation = $color.GetSaturation()
    $brightness = $color.GetBrightness()

    if ($hue -lt 170 -or $hue -gt 240 -or $saturation -lt 0.16) {
        return $color
    }

    $targetHue = 30.0
    $chroma = (1.0 - [Math]::Abs(2.0 * $brightness - 1.0)) * $saturation
    $segment = $targetHue / 60.0
    $x = $chroma * (1.0 - [Math]::Abs(($segment % 2.0) - 1.0))
    $match = $brightness - $chroma / 2.0

    $red = $chroma
    $green = $x
    $blue = 0.0

    return [System.Drawing.Color]::FromArgb(
        $color.A,
        [Math]::Round(255.0 * ($red + $match)),
        [Math]::Round(255.0 * ($green + $match)),
        [Math]::Round(255.0 * ($blue + $match))
    )
}

foreach ($source in $sources) {
    $outputDirectory = Split-Path -Parent $source.Output
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

    $inputImage = [System.Drawing.Bitmap]::new($source.Input)
    $outputImage = [System.Drawing.Bitmap]::new(
        $inputImage.Width,
        $inputImage.Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        for ($y = 0; $y -lt $inputImage.Height; $y++) {
            for ($x = 0; $x -lt $inputImage.Width; $x++) {
                $outputImage.SetPixel($x, $y, (Convert-BlueToOrange $inputImage.GetPixel($x, $y)))
            }
        }

        $outputImage.Save($source.Output, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $outputImage.Dispose()
        $inputImage.Dispose()
    }
}
