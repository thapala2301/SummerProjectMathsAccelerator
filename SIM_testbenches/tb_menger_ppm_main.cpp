// Verilator testbench: repeat_mod_cell x3 + menger_sdf -> PPM slice
// Renders a 256x256 XY slice at z=0, world coords [-3,3]x[-3,3]
// Also runs spot-checks on known analytic SDF values.
//
// Build & run: make menger_ppm   (from SIM/)
// Output: menger_rtl.ppm — open with any image viewer

#include "Vmenger_ppm_top.h"
#include "verilated.h"
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <fstream>

// -----------------------------------------------------------------------
// FP27 <-> float conversion
// FP27: bit26=sign, bits[25:18]=biased_exp (same bias as FP32), bits[17:0]=mantissa MSBs
// -----------------------------------------------------------------------
static uint32_t f2fp27(float f) {
    if (f == 0.0f) return 0;
    uint32_t b; memcpy(&b, &f, 4);
    uint32_t sign = (b >> 31) & 1;
    uint32_t exp  = (b >> 23) & 0xFF;
    uint32_t mant = (b & 0x7FFFFF) >> 5; // top 18 bits
    return (sign << 26) | (exp << 18) | mant;
}

static float fp272f(uint32_t v) {
    uint32_t exp = (v >> 18) & 0xFF;
    if (exp == 0) return 0.0f;
    uint32_t sign = (v >> 26) & 1;
    uint32_t mant = (v & 0x3FFFF) << 5; // extend to 23b
    uint32_t b = (sign << 31) | (exp << 23) | mant;
    float f; memcpy(&f, &b, 4);
    return f;
}

static void tick(Vmenger_ppm_top* top) {
    top->clk = 0; top->eval();
    Verilated::timeInc(1);
    top->clk = 1; top->eval();
    Verilated::timeInc(1);
}

// -----------------------------------------------------------------------
// Spot-check helpers
// -----------------------------------------------------------------------
static int g_fails = 0;

static void check(const char* label, float got, float expected, float tol) {
    float err = std::fabs(got - expected);
    if (err <= tol) {
        std::printf("  PASS  %-30s = %+.4f (expected %+.4f)\n", label, got, expected);
    } else {
        std::printf("  FAIL  %-30s = %+.4f (expected %+.4f, err %.4f)\n",
                    label, got, expected, err);
        g_fails++;
    }
}

static void check_sign(const char* label, float got, bool expect_negative) {
    bool is_neg = got < 0.0f;
    if (is_neg == expect_negative) {
        std::printf("  PASS  %-30s = %+.4f (%s)\n", label, got,
                    expect_negative ? "inside (neg)" : "outside (pos)");
    } else {
        std::printf("  FAIL  %-30s = %+.4f (expected %s)\n", label, got,
                    expect_negative ? "negative/inside" : "positive/outside");
        g_fails++;
    }
}

// -----------------------------------------------------------------------
// Run the pipeline with a sequence of (x,y,z) points and return outputs
// Streaming: one new input per clock, output arrives PIPELINE_LAT later
// -----------------------------------------------------------------------
// Measured by probe_latency() below. Verilator reads sdf_out immediately after
// posedge eval(), so the observable latency = RTL_LAT - 1 = 101-1 = 100.
static constexpr int PIPELINE_LAT = 100; // measured: RTL 101 cycles → testbench 100

static std::vector<float> run_pipeline(
    Vmenger_ppm_top* top,
    const std::vector<std::tuple<float,float,float>>& pts)
{
    int N = (int)pts.size();
    std::vector<float> out(N, 0.0f);

    for (int cycle = 0; cycle < N + PIPELINE_LAT + 2; ++cycle) {
        // Set inputs for this cycle (or zero after all points fed)
        int in_i = cycle;
        if (in_i < N) {
            auto [x,y,z] = pts[in_i];
            top->px = f2fp27(x);
            top->py = f2fp27(y);
            top->pz = f2fp27(z);
        } else {
            top->px = top->py = top->pz = 0;
        }

        tick(top);

        // Collect output for point that was driven PIPELINE_LAT cycles ago
        int out_i = cycle - PIPELINE_LAT;
        if (out_i >= 0 && out_i < N)
            out[out_i] = fp272f(top->sdf_out);
    }

    return out;
}

// -----------------------------------------------------------------------
// PPM render: 256x256 XY slice at z=0 over [-3,3] x [-3,3]
// Coloring: inside solid (d<0) -> dark; outside/tunnel (d>0) -> light
// Shows 3x3 grid of repeated Menger cells (each cell is 2x2 world units)
// -----------------------------------------------------------------------
static void write_ppm(Vmenger_ppm_top* top) {
    constexpr int W = 256, H = 256;
    constexpr float X0 = -3.0f, X1 = 3.0f;
    constexpr float Y0 = -3.0f, Y1 = 3.0f;
    constexpr float Z  =  0.0f;

    std::vector<std::tuple<float,float,float>> pts;
    pts.reserve(W * H);
    for (int row = 0; row < H; ++row)
        for (int col = 0; col < W; ++col)
            pts.emplace_back(
                X0 + (X1-X0) * col / (W-1),
                Y1 - (Y1-Y0) * row / (H-1), // y up
                Z);

    std::printf("Running pipeline for %dx%d = %d pixels (%d cycles)...\n",
                W, H, W*H, W*H + PIPELINE_LAT + 2);
    auto sdf = run_pipeline(top, pts);

    // Find range for normalization
    float dmin = sdf[0], dmax = sdf[0];
    for (float v : sdf) { dmin = std::min(dmin, v); dmax = std::max(dmax, v); }
    std::printf("SDF range: [%.4f, %.4f]\n", dmin, dmax);

    std::vector<uint8_t> img(W * H * 3);
    for (int i = 0; i < W*H; ++i) {
        float d = sdf[i];
        uint8_t r, g, b;
        if (d < 0.0f) {
            // Inside solid: dark background, slight gradient shows depth
            float t = std::min(1.0f, -d / 1.0f);           // 0=surface, 1=deep
            uint8_t v = (uint8_t)(30 + (1.0f-t) * 100);    // 30-130
            r = v; g = v; b = (uint8_t)(v + 20);           // slightly blue tint
        } else {
            // Inside tunnel / outside box: bright, red tint near surface
            float t = std::min(1.0f, d / 0.5f);             // 0=surface, 1=far
            r = (uint8_t)(255);
            g = (uint8_t)(200 - t * 180);
            b = (uint8_t)(200 - t * 200);
        }
        img[i*3+0] = r; img[i*3+1] = g; img[i*3+2] = b;
    }

    std::ofstream f("menger_rtl.ppm", std::ios::binary);
    f << "P6\n" << W << " " << H << "\n255\n";
    f.write(reinterpret_cast<const char*>(img.data()), img.size());
    std::printf("Wrote menger_rtl.ppm (%dx%d)\n", W, H);
}

// -----------------------------------------------------------------------
// Spot checks: known analytic Menger SDF values (after repeat folding)
// World point -> repeat -> menger_sdf -> compare
// -----------------------------------------------------------------------
static void run_spot_checks(Vmenger_ppm_top* top) {
    std::printf("\n--- Spot checks ---\n");

    // Point, expected SDF, tolerance, description
    // PIPELINE_LAT=100 means: after tick at cycle 100, sdf_out = SDF(pts[0]).
    // Analytical values computed by tracing repeat_mod_cell → menger_sdf by hand.
    struct Case { float x,y,z; float exp; float tol; const char* label; };
    Case cases[] = {
        // World (0,0,0): repeat → (0,0,0). All levels: cross=-1 (solid).
        // SDF = max(box=-1, neg_c1=-1, neg_c2=-1/3, neg_c3=-1/9) = -1/9 ≈ -0.111
        { 0.0f, 0.0f, 0.0f,  -0.111f, 0.06f, "origin (0,0,0)" },

        // World (0.5,0.5,0): repeat → (0.5,0.5,0). Level-1 z-tunnel: cross=0.5, neg_c1=0.5.
        // SDF = max(-0.5, 0.5) = +0.5 (inside z-direction cross tunnel)
        { 0.5f, 0.5f, 0.0f,  0.5f,   0.06f, "z-tunnel junction (0.5,0.5,0)" },

        // World (0.9,0.9,0): repeat → (0.9,0.9,0). Level-1 z-tunnel: cross=0.7, neg_c1=0.3.
        // Level-2 z-tunnel: 0.9×3=2.7, mod2=0.7, cross=0.1, neg_c2=0.3.
        // SDF = max(-0.1, 0.3) = +0.3 (inside level-1 AND level-2 cross tunnels)
        { 0.9f, 0.9f, 0.0f,  0.3f,   0.06f, "tunnel junction (0.9,0.9,0)" },

        // World (1.5,0,0): repeat: 1.5+1=2.5, mod2=0.5, sub=−0.5. Folded q=(−0.5,0,0).
        // Not in any tunnel (all neg_ci negative). SDF = max(-0.5, -1/9) = -1/9 ≈ -0.111
        { 1.5f, 0.0f, 0.0f,  -0.111f, 0.06f, "repeat wrap (1.5,0,0) -> q=(-0.5,0,0)" },

        // World (2.5,0,0): repeat: 2.5+1=3.5, mod2=1.5, sub=0.5. Folded q=(0.5,0,0).
        // Symmetric to (1.5,0,0) case. SDF = -1/9 ≈ -0.111
        { 2.5f, 0.0f, 0.0f,  -0.111f, 0.06f, "adjacent cell (2.5,0,0) = q=(0.5,0,0)" },

        // World (0,0,1): repeat: 1+1=2, mod2=0, sub=-1. Folded qz=-1 (box surface).
        // box_d = max(-1,-1,1-1) = 0. All neg_ci ≤ 0. SDF = 0.0 (on box surface)
        { 0.0f, 0.0f, 1.0f,   0.0f,   0.06f, "box face z=1 (local)" },
    };

    std::vector<std::tuple<float,float,float>> pts;
    for (auto& c : cases) pts.emplace_back(c.x, c.y, c.z);
    auto out = run_pipeline(top, pts);

    for (int i = 0; i < (int)(sizeof(cases)/sizeof(cases[0])); ++i) {
        auto& c = cases[i];
        if (std::isnan(c.exp)) {
            check_sign(c.label, out[i], /*expect_negative=*/false);
        } else if (c.exp < -900.0f) {
            check_sign(c.label, out[i], true);
        } else {
            check(c.label, out[i], c.exp, c.tol);
        }
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto* top = new Vmenger_ppm_top;

    // Flush the full 101-stage pipeline with zero inputs before any test
    top->clk = 0; top->px = top->py = top->pz = 0;
    for (int i = 0; i < 110; ++i) tick(top);

    run_spot_checks(top);
    write_ppm(top);

    top->final();
    delete top;

    std::printf("\n%s (%d failures)\n",
                g_fails ? "FAIL" : "PASS", g_fails);
    return g_fails ? 1 : 0;
}
