#include "Vfp_test_top.h"
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

static void tick(Vfp_test_top* top) {
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

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto* top = new Vfp_test_top;

    constexpr uint32_t K_FP_ZERO     = 0x0000000;
    constexpr uint32_t K_FP_ONE      = 0x1FC0000;
    constexpr uint32_t K_FP_TWO      = 0x2000000;
    constexpr uint32_t K_FP_THREE    = 0x2020000;
    constexpr uint32_t K_FP_HALF     = 0x1F80000;
    constexpr uint32_t K_FP_NEG_HALF = 0x5F80000;
    constexpr uint32_t K_FP_NEG_ONE  = 0x5FC0000;
    constexpr uint32_t K_FP_1P5      = 0x1FE0000;
    constexpr uint32_t K_FP_4P5      = 0x2048000;
    constexpr uint32_t K_FP_FOUR     = 0x2040000;

    int fails = 0;

    top->mul_a = 0; top->mul_b = 0;
    top->add_a = 0; top->add_b = 0;
    top->sub_a = 0; top->sub_b = 0;
    top->isqrt_in = 0;
    top->int_in = 0;

    for (int i = 0; i < 4; ++i) tick(top);

    std::printf("\nTEST fp_mul\n");
    top->mul_a = K_FP_TWO; top->mul_b = K_FP_THREE;
    for (int i = 0; i < 3; ++i) tick(top);
    fails += check_fp("2.0 * 3.0", top->mul_out, 6.0, 0.01);

    top->mul_a = K_FP_HALF; top->mul_b = K_FP_HALF;
    for (int i = 0; i < 3; ++i) tick(top);
    fails += check_fp("0.5 * 0.5", top->mul_out, 0.25, 0.001);

    top->mul_a = K_FP_NEG_ONE; top->mul_b = K_FP_4P5;
    for (int i = 0; i < 3; ++i) tick(top);
    fails += check_fp("-1.0 * 4.5", top->mul_out, -4.5, 0.01);

    std::printf("\nTEST fp_add\n");
    top->add_a = K_FP_ONE; top->add_b = K_FP_TWO;
    for (int i = 0; i < 5; ++i) tick(top);
    fails += check_fp("1.0 + 2.0", top->add_out, 3.0, 0.01);

    top->add_a = K_FP_HALF; top->add_b = K_FP_NEG_HALF;
    for (int i = 0; i < 5; ++i) tick(top);
    fails += check_fp("0.5 + (-0.5)", top->add_out, 0.0, 0.001);

    top->add_a = K_FP_1P5; top->add_b = K_FP_TWO;
    for (int i = 0; i < 5; ++i) tick(top);
    fails += check_fp("1.5 + 2.0", top->add_out, 3.5, 0.01);

    std::printf("\nTEST fp_sub\n");
    top->sub_a = K_FP_1P5; top->sub_b = K_FP_HALF;
    for (int i = 0; i < 5; ++i) tick(top);
    fails += check_fp("1.5 - 0.5", top->sub_out, 1.0, 0.01);

    top->sub_a = K_FP_TWO; top->sub_b = K_FP_THREE;
    for (int i = 0; i < 5; ++i) tick(top);
    fails += check_fp("2.0 - 3.0", top->sub_out, -1.0, 0.01);

    std::printf("\nTEST fp_isqrt\n");
    top->isqrt_in = K_FP_ONE;
    tick(top);
    for (int i = 0; i < 9; ++i) tick(top);
    fails += check_fp("1/sqrt(1.0)", top->isqrt_out, 1.0, 0.01);

    top->isqrt_in = K_FP_FOUR;
    tick(top);
    for (int i = 0; i < 9; ++i) tick(top);
    fails += check_fp("1/sqrt(4.0)", top->isqrt_out, 0.5, 0.01);

    top->isqrt_in = K_FP_ZERO;
    tick(top);

    std::printf("\nTEST int2fp\n");
    top->int_in = static_cast<uint32_t>(536870912);
    top->eval();
    fails += check_fp("int2fp(1.0)", top->int_out, 1.0, 0.01);

    top->int_in = static_cast<uint32_t>(268435456);
    top->eval();
    fails += check_fp("int2fp(0.5)", top->int_out, 0.5, 0.01);

    top->int_in = static_cast<uint32_t>(-536870912);
    top->eval();
    fails += check_fp("int2fp(-1.0)", top->int_out, -1.0, 0.01);

    top->int_in = 0;
    top->eval();
    fails += check_fp("int2fp(0.0)", top->int_out, 0.0, 0.01);

    std::printf("\nAll FP tests done (%s)\n", fails ? "FAIL" : "PASS");

    top->final();
    delete top;
    return fails ? 1 : 0;
}
