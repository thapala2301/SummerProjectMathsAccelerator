$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $PSScriptRoot

$RTL  = "$repoRoot/RTL"
$FP   = "$RTL/FP_Lib"
$CORE = "$RTL/core"
$CTRL = "$RTL/control"
$VID  = "$RTL/video"
$SDF  = "$RTL/sdf"

$sources = @(
    "sim_top.sv",
    "$CORE/march_core.sv",
    "$CORE/repeat_mod_cell.sv",
    "$CORE/ray_gen.sv",
    "$CORE/state_pipe.v",
    "$CORE/state_pipe_unpacked_array.sv",
    "$SDF/menger_sdf.sv",
    "$CTRL/pixel_dispatch.sv",
    "$CTRL/feedback_ctrl.sv",
    "$CTRL/FIFO.sv",
    "$VID/ddr_rgb_writer.sv",
    "$VID/palette.sv",
    "$FP/fp_add.v",
    "$FP/fp_sub.v",
    "$FP/fp_mul.v",
    "$FP/fp_abs.v",
    "$FP/fp_min.v",
    "$FP/fp_max.v",
    "$FP/fp_isqrt.v",
    "$FP/fp_length.v",
    "$FP/fp_negate.v",
    "$FP/fp_mod2.v",
    "$FP/fp_normalize.sv",
    "$FP/fp_mul_vec3_mat33.sv",
    "$FP/int2fp.v",
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
