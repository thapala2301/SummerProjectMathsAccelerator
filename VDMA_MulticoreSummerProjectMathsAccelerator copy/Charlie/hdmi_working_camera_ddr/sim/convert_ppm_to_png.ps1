param(
    [string[]]$InputFiles = @("frame.ppm", "screen.ppm")
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function Convert-P3PpmToPng {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "File not found: $InputPath"
    }

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $InputPath) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }

        foreach ($part in ($trimmed -split '\s+')) {
            if ($part.Length -gt 0) {
                [void]$tokens.Add($part)
            }
        }
    }

    if ($tokens.Count -lt 4 -or $tokens[0] -ne 'P3') {
        throw "Unsupported PPM format in $InputPath. Expected plain-text P3."
    }

    $width = [int]$tokens[1]
    $height = [int]$tokens[2]
    $maxVal = [int]$tokens[3]

    if ($maxVal -ne 255) {
        throw "Unsupported max value $maxVal in $InputPath. Expected 255."
    }

    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    try {
        $idx = 4
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $r = [int]$tokens[$idx]; $idx++
                $g = [int]$tokens[$idx]; $idx++
                $b = [int]$tokens[$idx]; $idx++
                $bitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($r, $g, $b))
            }
        }

        $outputPath = [System.IO.Path]::ChangeExtension($InputPath, 'png')
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "Wrote $outputPath"
    }
    finally {
        $bitmap.Dispose()
    }
}

foreach ($inputFile in $InputFiles) {
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($inputFile)) {
        $inputFile
    } else {
        Join-Path $PSScriptRoot $inputFile
    }

    Convert-P3PpmToPng -InputPath $resolvedPath
}
