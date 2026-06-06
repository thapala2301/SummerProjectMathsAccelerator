#include "Vmarch_trace_top.h"
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

static void tick(Vmarch_trace_top* top) {
    top->clk = 0;
    top->eval();
    Verilated::timeInc(1);
    top->clk = 1;
    top->eval();
    Verilated::timeInc(1);
}

static void clear_inputs(Vmarch_trace_top* top) {
    top->in_x = 0;
    top->in_y = 0;
    top->in_pix_id = 0;
    top->in_pos_x = 0;
    top->in_pos_y = 0;
    top->in_pos_z = 0;
    top->in_ray_dir_x = 0;
    top->in_ray_dir_y = 0;
    top->in_ray_dir_z = 0;
    top->in_iter = 0;
    top->in_valid = 0;
}

static int run_pixel(Vmarch_trace_top* top, uint16_t px, uint16_t py, uint32_t pid, const char* label) {
    clear_inputs(top);
    top->in_x = px;
    top->in_y = py;
    top->in_pix_id = pid;
    top->in_iter = 0;
    top->in_valid = 1;
    tick(top);
    top->in_valid = 0;

    int steps = 0;
    int cycles = 0;
    while (cycles < 2000) {
        tick(top);
        ++cycles;

        if (top->fb_valid) {
            double src_x = fp27(top->dbg_src_pos_x);
            double src_y = fp27(top->dbg_src_pos_y);
            double src_z = fp27(top->dbg_src_pos_z);
            double dist = fp27(top->dbg_d3_dist);
            double x = fp27(top->fb_pos_x);
            double y = fp27(top->fb_pos_y);
            double z = fp27(top->fb_pos_z);
            double dx = fp27(top->fb_ray_dir_x);
            double dy = fp27(top->fb_ray_dir_y);
            double dz = fp27(top->fb_ray_dir_z);
            std::printf(
                "  step %d iter=%u src=(%.4f, %.4f, %.4f) dist=%.4f pos=(%.4f, %.4f, %.4f) dir=(%.4f, %.4f, %.4f)\n",
                steps, top->fb_iter, src_x, src_y, src_z, dist, x, y, z, dx, dy, dz
            );

            top->in_x = 0;
            top->in_y = 0;
            top->in_pix_id = top->fb_pix_id;
            top->in_pos_x = top->fb_pos_x;
            top->in_pos_y = top->fb_pos_y;
            top->in_pos_z = top->fb_pos_z;
            top->in_ray_dir_x = top->fb_ray_dir_x;
            top->in_ray_dir_y = top->fb_ray_dir_y;
            top->in_ray_dir_z = top->fb_ray_dir_z;
            top->in_iter = top->fb_iter;
            top->in_valid = 1;
            tick(top);
            top->in_valid = 0;
            ++steps;
        }

        if (top->pix_done) {
            std::printf("  DONE  %s pix_id=%u out_iter=%u after %d feedback steps\n",
                        label, top->out_pix_id, top->out_iter, steps);
            return 0;
        }
    }

    std::printf("  FAIL  %s did not complete within cycle budget\n", label);
    return 1;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    int fails = 0;

    {
        auto* top = new Vmarch_trace_top;
        top->clk = 0;
        top->rst_n = 0;
        clear_inputs(top);
        for (int i = 0; i < 8; ++i) tick(top);
        top->rst_n = 1;
        for (int i = 0; i < 4; ++i) tick(top);

        std::printf("\nTRACE centre pixel\n");
        fails += run_pixel(top, 640, 360, 1, "centre");

        top->final();
        delete top;
    }

    {
        auto* top = new Vmarch_trace_top;
        top->clk = 0;
        top->rst_n = 0;
        clear_inputs(top);
        for (int i = 0; i < 8; ++i) tick(top);
        top->rst_n = 1;
        for (int i = 0; i < 4; ++i) tick(top);

        std::printf("\nTRACE row-above-centre pixel\n");
        fails += run_pixel(top, 640, 358, 2, "row-above-centre");

        top->final();
        delete top;
    }

    {
        auto* top = new Vmarch_trace_top;
        top->clk = 0;
        top->rst_n = 0;
        clear_inputs(top);
        for (int i = 0; i < 8; ++i) tick(top);
        top->rst_n = 1;
        for (int i = 0; i < 4; ++i) tick(top);

        std::printf("\nTRACE row-below-centre pixel\n");
        fails += run_pixel(top, 640, 362, 3, "row-below-centre");

        top->final();
        delete top;
    }

    return fails ? 1 : 0;
}
