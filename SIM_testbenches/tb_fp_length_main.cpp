#include "Vfp_length_test_top.h"
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

static void tick(Vfp_length_test_top* top) {
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

static int drive_vec(
    Vfp_length_test_top* top,
    uint32_t x,
    uint32_t y,
    uint32_t z,
    const char* label,
    double expected,
    double tol
) {
    top->x = x;
    top->y = y;
    top->z = z;
    tick(top);
    for (int i = 0; i < 24; ++i) tick(top);
    return check_fp(label, top->out, expected, tol);
}

static void pulse_probe(Vfp_length_test_top* top, uint32_t x, uint32_t y, uint32_t z) {
    constexpr uint32_t K_FP_ZERO = 0x0000000;
    std::printf("\nLATENCY probe for one-cycle fp_length pulse\n");
    top->x = x;
    top->y = y;
    top->z = z;
    tick(top);
    top->x = K_FP_ZERO;
    top->y = K_FP_ZERO;
    top->z = K_FP_ZERO;
    for (int cycle = 1; cycle <= 32; ++cycle) {
        tick(top);
        if (cycle >= 18 && cycle <= 28) {
            std::printf("  cycle %+d len_out=%.6f\n", cycle, fp27(top->out));
        }
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto* top = new Vfp_length_test_top;
    int fails = 0;

    constexpr uint32_t K_FP_ZERO      = 0x0000000;
    constexpr uint32_t K_FP_ONEP5     = 0x1FE0000;
    constexpr uint32_t K_FP_THREE     = 0x2020000;
    constexpr uint32_t K_FP_DIAG_HALF = 0x1F9A828;
    constexpr uint32_t K_FP_DIAG_SURF = 0x1FC3E1E;
    constexpr uint32_t K_FP_DIAG_OUT  = 0x2003E1E;

    top->clk = 0;
    top->x = K_FP_ZERO;
    top->y = K_FP_ZERO;
    top->z = K_FP_ZERO;
    for (int i = 0; i < 6; ++i) tick(top);

    std::printf("\nTEST fp_length\n");
    fails += drive_vec(top, K_FP_ZERO, K_FP_ZERO, K_FP_ZERO, "len(0,0,0)", 0.0, 0.01);
    fails += drive_vec(top, K_FP_ONEP5, K_FP_ZERO, K_FP_ZERO, "len(1.5,0,0)", 1.5, 0.03);
    fails += drive_vec(top, K_FP_THREE, K_FP_ZERO, K_FP_ZERO, "len(3,0,0)", 3.0, 0.05);
    fails += drive_vec(top, K_FP_DIAG_HALF, K_FP_ZERO, K_FP_DIAG_HALF, "len(0.707,0,0.707)", 1.0, 0.05);
    fails += drive_vec(top, K_FP_DIAG_SURF, K_FP_ZERO, K_FP_DIAG_SURF, "len(1.061,0,1.061)", 1.5, 0.05);
    fails += drive_vec(top, K_FP_DIAG_OUT, K_FP_ZERO, K_FP_DIAG_OUT, "len(2.121,0,2.121)", 3.0, 0.08);

    pulse_probe(top, K_FP_DIAG_OUT, K_FP_ZERO, K_FP_DIAG_OUT);

    std::printf("\nAll fp_length tests done (%s)\n", fails ? "FAIL" : "PASS");
    top->final();
    delete top;
    return fails ? 1 : 0;
}
