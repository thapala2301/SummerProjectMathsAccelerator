#include "Vray_gen_test_top.h"
#include "verilated.h"
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <string>

static double fp27(uint32_t f) {
    uint32_t exp = (f >> 18U) & 0xffU;
    if (exp == 0U) return 0.0;
    int e = static_cast<int>(exp) - 127;
    double m = 1.0 + static_cast<double>(f & 0x3ffffU) / 262144.0;
    double v = std::ldexp(m, e);
    return ((f >> 26U) & 1U) ? -v : v;
}

static void tick(Vray_gen_test_top* top) {
    top->clk = 0;
    top->eval();
    Verilated::timeInc(1);
    top->clk = 1;
    top->eval();
    Verilated::timeInc(1);
}

static void set_identity_camera(Vray_gen_test_top* top) {
    constexpr uint32_t K_FP_ONE  = 0x1FC0000;
    constexpr uint32_t K_FP_NEG1 = 0x5FC0000;
    constexpr uint32_t K_FP_TWO  = 0x2000000;
    constexpr uint32_t K_FP_ZERO = 0x0000000;

    top->lookat0 = K_FP_ONE;  top->lookat1 = K_FP_ZERO; top->lookat2 = K_FP_ZERO;
    top->lookat3 = K_FP_ZERO; top->lookat4 = K_FP_ONE;  top->lookat5 = K_FP_ZERO;
    top->lookat6 = K_FP_ZERO; top->lookat7 = K_FP_ZERO; top->lookat8 = K_FP_NEG1;
    top->cam_origin0 = K_FP_ZERO;
    top->cam_origin1 = K_FP_ZERO;
    top->cam_origin2 = K_FP_TWO;
}

static int send_pixel(
    Vray_gen_test_top* top,
    uint16_t px,
    uint16_t py,
    uint32_t pid,
    const char* label,
    bool check_dir,
    double exp_dx,
    double exp_dy,
    double exp_dz
) {
    int fails = 0;

    top->pix_x = px;
    top->pix_y = py;
    top->pix_id_in = pid;
    top->valid_in = 1;
    tick(top);
    top->valid_in = 0;

    bool seen = false;
    for (int i = 0; i < 80; ++i) {
        tick(top);
        if (top->valid_out) {
            seen = true;
            break;
        }
    }

    if (!seen) {
        std::printf("  FAIL  %s: valid_out not asserted\n", label);
        return 1;
    }

    double dx = fp27(top->ray_dir0);
    double dy = fp27(top->ray_dir1);
    double dz = fp27(top->ray_dir2);
    double mag = std::sqrt(dx * dx + dy * dy + dz * dz);
    double err = std::fabs(mag - 1.0);

    if (err < 0.02) {
        std::printf("  PASS  %s unit length |ray|=%.4f\n", label, mag);
    } else {
        std::printf("  FAIL  %s unit length |ray|=%.4f\n", label, mag);
        ++fails;
    }

    if (check_dir) {
        err = std::fabs(dx - exp_dx);
        if (err < 0.02) std::printf("  PASS  %s dir.x=%.4f\n", label, dx);
        else { std::printf("  FAIL  %s dir.x=%.4f expected %.4f\n", label, dx, exp_dx); ++fails; }

        err = std::fabs(dy - exp_dy);
        if (err < 0.02) std::printf("  PASS  %s dir.y=%.4f\n", label, dy);
        else { std::printf("  FAIL  %s dir.y=%.4f expected %.4f\n", label, dy, exp_dy); ++fails; }

        err = std::fabs(dz - exp_dz);
        if (err < 0.02) std::printf("  PASS  %s dir.z=%.4f\n", label, dz);
        else { std::printf("  FAIL  %s dir.z=%.4f expected %.4f\n", label, dz, exp_dz); ++fails; }
    }

    if (top->pix_id_out == pid) {
        std::printf("  PASS  %s pix_id=%u correct\n", label, pid);
    } else {
        std::printf("  FAIL  %s pix_id=%u expected %u\n", label, top->pix_id_out, pid);
        ++fails;
    }

    return fails;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto* top = new Vray_gen_test_top;
    int fails = 0;

    top->clk = 0;
    top->rst_n = 0;
    top->pix_x = 0;
    top->pix_y = 0;
    top->pix_id_in = 0;
    top->valid_in = 0;
    top->lookat0 = top->lookat1 = top->lookat2 = 0;
    top->lookat3 = top->lookat4 = top->lookat5 = 0;
    top->lookat6 = top->lookat7 = top->lookat8 = 0;
    top->cam_origin0 = top->cam_origin1 = top->cam_origin2 = 0;

    for (int i = 0; i < 4; ++i) tick(top);
    top->rst_n = 1;
    tick(top);
    tick(top);
    set_identity_camera(top);
    tick(top);
    tick(top);
    tick(top);

    std::printf("\nTEST 1 pipeline_ready\n");
    if (top->pipeline_ready == 1) {
        std::printf("  PASS  pipeline_ready = 1\n");
    } else {
        std::printf("  FAIL  pipeline_ready = %u\n", top->pipeline_ready);
        ++fails;
    }

    std::printf("\nTEST 2 near-centre pixel with pixel-centre sampling\n");
    fails += send_pixel(
        top, 640, 360, 1, "near-centre", true,
        0.4082, -0.4082, -0.8165
    );

    tick(top);
    tick(top);

    std::printf("\nTEST 3 top-left unit length\n");
    fails += send_pixel(top, 0, 0, 0, "top-left", false, 0.0, 0.0, 0.0);

    tick(top);
    tick(top);

    std::printf("\nTEST 4 bottom-right unit length\n");
    fails += send_pixel(top, 1279, 719, 921599, "bot-right", false, 0.0, 0.0, 0.0);

    tick(top);
    tick(top);

    std::printf("\nTEST 5 cam_origin passthrough\n");
    top->pix_x = 640;
    top->pix_y = 360;
    top->pix_id_in = 99;
    top->valid_in = 1;
    tick(top);
    top->valid_in = 0;

    bool seen = false;
    for (int i = 0; i < 80; ++i) {
        tick(top);
        if (top->valid_out) {
            seen = true;
            break;
        }
    }

    if (!seen) {
        std::printf("  FAIL  cam_origin passthrough: valid_out not asserted\n");
        ++fails;
    } else {
        double oz = fp27(top->ray_orig2);
        double err = std::fabs(oz - 2.0);
        if (err < 0.01) {
            std::printf("  PASS  ray_orig.z=%.4f\n", oz);
        } else {
            std::printf("  FAIL  ray_orig.z=%.4f expected 2.0\n", oz);
            ++fails;
        }
    }

    std::printf("\nAll ray_gen tests done (%s)\n", fails ? "FAIL" : "PASS");

    top->final();
    delete top;
    return fails ? 1 : 0;
}
