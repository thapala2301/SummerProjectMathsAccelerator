// Neural SDF verification sim
// Bakes SDF into BRAM, queries 256x256 grid at z=0, writes PPM
// Expected output: circle (sphere cross-section) if network learned correctly

//REWRITE....!!
#include "Vneural_sdf_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cmath>
#include <vector>

const uint32_t W = 256;
const uint32_t H = 256;
const uint32_t N_PIX = W * H;

uint32_t float_to_fp27(float v) {
    if (v == 0.0f) return 0;
    uint32_t sign = (v < 0) ? 1 : 0;
    float mag = fabsf(v);
    int exp = (int)floorf(log2f(mag));
    float mant = mag / powf(2.0f, (float)exp) - 1.0f;
    uint32_t mant_bits = (uint32_t)(mant * (float)(1 << 18));
    return (sign << 26) | ((uint32_t)(exp + 127) << 18) | (mant_bits & 0x3FFFF);
}

float fp27_to_float(uint32_t fp) {
    if (fp == 0) return 0.0f;
    int sign = (fp >> 26) & 1;
    int exp  = (fp >> 18) & 0xFF;
    float mant = 1.0f + (float)(fp & 0x3FFFF) / (float)(1 << 18);
    float val  = mant * powf(2.0f, (float)(exp - 127));
    return sign ? -val : val;
}

struct RGB { uint8_t r, g, b; };

RGB dist_to_rgb(float d) {
    if (d < -0.05f) return {0, 0, 150};        // inside: dark blue
    if (d <  0.0f)  return {100, 100, 255};     // near surface inside: light blue
    if (d <  0.05f) return {255, 255, 255};     // surface: white
    float fade = fminf(d / 2.0f, 1.0f);
    uint8_t v = (uint8_t)(255 * (1.0f - fade));
    return {v, v, v};                           // outside: grey fading to black
}

int main() {
    Vneural_sdf_top* dut = new Vneural_sdf_top;
    std::vector<float> frame(N_PIX, 0.0f);

    // reset
    dut->rst = 1; dut->clk = 0; dut->query_valid = 0;
    for (int i = 0; i < 20; i++) { dut->clk ^= 1; dut->eval(); }
    dut->rst = 0;

    // wait for baking_done — check every rising edge (1-clock pulse)
    printf("Baking neural SDF (32^3 = 32768 points)...\n");
    bool baked = false;
    long long clk_count = 0;
    while (!baked) {
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
        if (dut->baking_done) baked = true;
        clk_count++;
        if (clk_count % 1000000 == 0)
            printf("  %lld M clocks...\n", clk_count / 1000000);
    }
    printf("Baking done after %lld clocks.\n", clk_count);

    // query 256x256 grid at z=0
    printf("Querying SDF grid...\n");
    for (uint32_t yi = 0; yi < H; yi++) {
        for (uint32_t xi = 0; xi < W; xi++) {
            float xw = -2.0f + xi * (4.0f / (W - 1));
            float yw = -2.0f + yi * (4.0f / (H - 1));

            // pulse query_valid for 1 clock
            dut->x = float_to_fp27(xw);
            dut->y = float_to_fp27(yw);
            dut->z = 0;
            dut->query_valid = 1;
            dut->clk = 0; dut->eval();
            dut->clk = 1; dut->eval();
            dut->query_valid = 0;

            // wait for dist_valid (1-clock pulse), timeout after 5000 clocks
            bool got = false;
            for (int t = 0; t < 5000 && !got; t++) {
                dut->clk = 0; dut->eval();
                dut->clk = 1; dut->eval();
                if (dut->dist_valid) {
                    frame[yi * W + xi] = fp27_to_float(dut->dist);
                    got = true;
                }
            }
        }
        if (yi % 32 == 0) printf("  row %d/256\n", yi);
    }

    // write PPM
    FILE* f = fopen("neural_frame.ppm", "w");
    fprintf(f, "P3\n%d %d\n255\n", W, H);
    for (uint32_t i = 0; i < N_PIX; i++) {
        RGB c = dist_to_rgb(frame[i]);
        fprintf(f, "%d %d %d\n", c.r, c.g, c.b);
    }
    fclose(f);
    printf("Written neural_frame.ppm\n");

    delete dut;
    return 0;
}
