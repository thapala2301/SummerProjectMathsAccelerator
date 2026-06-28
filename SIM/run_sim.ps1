$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $PSScriptRoot

$sources = @(
    "sim_top.sv",
    "$repoRoot/rtl/core/march_core.sv",
    "$repoRoot/rtl/core/repeat_cell.sv",
    "$repoRoot/rtl/sdf/scaffold_sdf.v",
    "$repoRoot/rtl/sdf/twisted_torus_sdf.v",
    "$repoRoot/rtl/core/state_pipe.v",
    "$repoRoot/rtl/core/ray_gen.sv",
    "$repoRoot/rtl/control/pixel_dispatch.sv",
    "$repoRoot/rtl/control/feedback_ctrl.sv",
    "$repoRoot/rtl/control/FIFO.sv",
    "$repoRoot/rtl/video/ddr_rgb_writer.sv",
    "$repoRoot/rtl/video/palette.sv",
    "$repoRoot/rtl/fp/fp_add.v",
    "$repoRoot/rtl/fp/fp_sub.v",
    "$repoRoot/rtl/fp/fp_mul.v",
    "$repoRoot/rtl/fp/fp_abs.v",
    "$repoRoot/rtl/fp/fp_min.v",
    "$repoRoot/rtl/fp/fp_max.v",
    "$repoRoot/rtl/fp/fp_isqrt.v",
    "$repoRoot/rtl/fp/fp_length.v",
    "$repoRoot/rtl/fp/fp_negate.v",
    "$repoRoot/rtl/fp/int2fp.v",
    "sim_main.cpp"
)

verilator --cc --exe --build -sv `
    --top-module sim_top `
    -Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH `
    -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE `
    -Wno-CASEX `
    @sources `
    -o Vsim_top

& ".\obj_dir\Vsim_top.exe"
& "$PSScriptRoot\convert_ppm_to_png.ps1"