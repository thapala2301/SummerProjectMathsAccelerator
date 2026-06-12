#include "Vscene_sdf_test_top.h"
#include "verilated.h"
#include <cmath>
#include <cstdint>
#include <cstdio>

static double fp27(uint32_t f) {
    uint32_t exp = (f >> 18U) & 0xffU;
    if (exp == 0U) return 0.0;
    int e = static_cast<int>(exp) - 127;
    double m = 1.0 + static_cast<double>(f & 0x3ffffU) / 262144.0;
    double v = std::ldexp(m, e);
    return ((f >> 26U) & 1U) ? -v : v;
}

static void tick(Vscene_sdf_test_top* top) {
    top->clk = 0;
    top->eval();
    Verilated::timeInc(1);
    top->clk = 1;
    top->eval();
    Verilated::timeInc(1);
}

static int check_fp(const char* label, uint32_t got, double expected, double tol) {
    double g = fp27(got);
    double err = std::fabs(g - expected);
    if (err <= tol) {
        std::printf("  PASS  %s = %.6f (expected %.6f)\n", label, g, expected);
        return 0;
    }
    std::printf("  FAIL  %s = %.6f (expected %.6f, err %.6f)\n", label, g, expected, err);
    return 1;
}

static int drive_point(
    Vscene_sdf_test_top* top,
    uint32_t px,
    uint32_t py,
    uint32_t pz,
    const char* label,
    double expected,
    double tol
) {
    top->px = px;
    top->py = py;
    top->pz = pz;
    tick(top);
    for (int i = 0; i < 39; ++i) tick(top);
    return check_fp(label, top->sdf_out, expected, tol);
}

static void pulse_latency_probe(Vscene_sdf_test_top* top, uint32_t px, uint32_t py, uint32_t pz) {
    constexpr uint32_t K_FP_ZERO = 0x0000000;

    std::printf("\nLATENCY probe for one-cycle pulse at input point\n");
    top->px = px;
    top->py = py;
    top->pz = pz;
    tick(top);

    top->px = K_FP_ZERO;
    top->py = K_FP_ZERO;
    top->pz = K_FP_ZERO;

    for (int cycle = 1; cycle <= 50; ++cycle) {
        tick(top);
        const double v = fp27(top->sdf_out);
        if ((cycle >= 34) && (cycle <= 44)) {
            std::printf("  cycle %+d sdf_out=%.6f\n", cycle, v);
        }
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto* top = new Vscene_sdf_test_top;
    int fails = 0;

    constexpr uint32_t K_FP_ZERO      = 0x0000000;
    constexpr uint32_t K_FP_ONE       = 0x1FC0000;
    constexpr uint32_t K_FP_ONEP5     = 0x1FE0000;
    constexpr uint32_t K_FP_THREE     = 0x2020000;
    constexpr uint32_t K_FP_NEGONE    = 0x5FC0000;
    constexpr uint32_t K_FP_DIAG_HALF = 0x1F9A828; // ~0.70710678
    constexpr uint32_t K_FP_DIAG_SURF = 0x1FC3E1E; // ~1.06066017
    constexpr uint32_t K_FP_DIAG_OUT  = 0x2003E1E; // ~2.12132034
    constexpr uint32_t K_FP_NDIAG_SURF = 0x5FC3E1E; // ~-1.06066017

    top->clk = 0;
    top->px = 0;
    top->py = 0;
    top->pz = 0;
    for (int i = 0; i < 4; ++i) tick(top);

    std::printf("\nTEST scene_sdf debug sphere\n");
    fails += drive_point(top, K_FP_ZERO, K_FP_ZERO, K_FP_ZERO, "sphere(0,0,0)", -1.5, 0.05);
    fails += drive_point(top, K_FP_ONEP5, K_FP_ZERO, K_FP_ZERO, "sphere(1.5,0,0)", 0.0, 0.05);
    fails += drive_point(top, K_FP_THREE, K_FP_ZERO, K_FP_ZERO, "sphere(3,0,0)", 1.5, 0.08);
    fails += drive_point(top, K_FP_NEGONE, K_FP_ZERO, K_FP_ZERO, "sphere(-1,0,0)", -0.5, 0.08);
    fails += drive_point(top, K_FP_DIAG_HALF, K_FP_ZERO, K_FP_DIAG_HALF,
                         "sphere(0.707,0,0.707)", -0.5, 0.08);
    fails += drive_point(top, K_FP_DIAG_SURF, K_FP_ZERO, K_FP_DIAG_SURF,
                         "sphere(1.061,0,1.061)", 0.0, 0.08);
    fails += drive_point(top, K_FP_DIAG_OUT, K_FP_ZERO, K_FP_DIAG_OUT,
                         "sphere(2.121,0,2.121)", 1.5, 0.12);
    fails += drive_point(top, K_FP_NDIAG_SURF, K_FP_ZERO, K_FP_NDIAG_SURF,
                         "sphere(-1.061,0,-1.061)", 0.0, 0.08);
    pulse_latency_probe(top, K_FP_ONE, K_FP_ZERO, K_FP_ZERO);

    std::printf("\nAll scene_sdf tests done (%s)\n", fails ? "FAIL" : "PASS");
    top->final();
    delete top;
    return fails ? 1 : 0;
}
