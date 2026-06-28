$macros = @(
    "TEST_SCENE_SDF",
    "TEST_BOX",
    "TEST_CAPPED_TORUS",
    "TEST_CAPSULE",
    "TEST_CHAIN_LINK",
    "TEST_CONE",
    "TEST_CYLINDER",
    "TEST_DEATH_STAR",
    "TEST_ELLIPSOID",
    "TEST_GYROID",
    "TEST_HYPERBOLOID",
    "TEST_MANDELBULB",
    "TEST_OCTAHEDRON",
    "TEST_PYRAMID",
    "TEST_ROUND_BOX",
    "TEST_SPHERE",
    "TEST_STAR",
    "TEST_TERM",
    "TEST_TORUS",
    "TEST_TRIANGULAR_PRISM",
    "TEST_TWISTED_TORUS",
    "TEST_VESICA"
)

$base_dir = "C:/Sakthi/Imperial/Year2/Final_Project/SummerProjectMathsAccelerator"
$rtl_dir = "$base_dir/Vincent/Hardware"
$tb_dir = "$base_dir/Sakthivel/testbenches"

Set-Location $tb_dir
if (Test-Path "work") { Remove-Item -Recurse -Force "work" }
vlib work

Write-Host "Compiling RTL files..."
vlog -work work "$rtl_dir/Floating_Point_Lib/*.v"
vlog -work work "$rtl_dir/RTL/Analytic_SSF/*.v"
vlog -work work "$rtl_dir/RTL/Analytic_SSF/*.sv"

$results = @()

foreach ($macro in $macros) {
    Write-Host "Testing $macro..."
    
    # Recompile testbench
    vlog -work work "+define+$macro" "$tb_dir/tb_analytic_sdf.sv"
    
    # Run simulation
    $output = vsim -c -do "run -all; quit" tb_analytic_sdf 2>&1
    
    if ($output -match "ALL TESTS PASSED") {
        Write-Host "-> $($macro): PASSED" -ForegroundColor Green
        $results += "$($macro): PASSED"
    }
    else {
        Write-Host "-> $($macro): FAILED" -ForegroundColor Red
        $results += "$($macro): FAILED"
        $output | Select-String "Error" | ForEach-Object { Write-Host $_.Line.Trim() -ForegroundColor Red }
    }
}

Write-Host "`n`nFINAL SUMMARY"
$results | ForEach-Object { Write-Host $_ }
