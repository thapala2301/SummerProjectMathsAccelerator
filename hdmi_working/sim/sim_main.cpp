#include "Vsim_top.h"
#include "verilated.h"

#include <array>
#include <cstdlib>
#include <cstdint>
#include <cstdio>
#include <vector>

namespace {

constexpr std::uint32_t kFrameW = 640;
constexpr std::uint32_t kFrameH = 360;
constexpr std::uint32_t kScreenW = 1280;
constexpr std::uint32_t kScreenH = 720;
constexpr std::uint32_t kPixelCount = kFrameW * kFrameH;

struct RGB {
    std::uint8_t r;
    std::uint8_t g;
    std::uint8_t b;
};

RGB iter_to_rgb(std::uint8_t iter) {
    if (iter >= 128) {
        return {0, 0, 0};
    }

    const std::uint32_t step = iter;
    const std::uint32_t rem_r = step % 50;
    const std::uint32_t rem_g = (step * 13) % 1000;
    const std::uint32_t rem_b = (step * 7) % 1000;

    return {
        static_cast<std::uint8_t>((rem_r * 255) / 50),
        static_cast<std::uint8_t>((rem_g * 255) / 1000),
        static_cast<std::uint8_t>((rem_b * 255) / 1000)
    };
}

void write_ppm(const char* path, std::uint32_t width, std::uint32_t height,
               const std::vector<RGB>& pixels) {
    FILE* f = std::fopen(path, "w");
    if (!f) {
        std::perror(path);
        std::exit(1);
    }

    std::fprintf(f, "P3\n%u %u\n255\n", width, height);
    for (const auto& pixel : pixels) {
        std::fprintf(f, "%u %u %u\n", pixel.r, pixel.g, pixel.b);
    }
    std::fclose(f);
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vsim_top* dut = new Vsim_top;
    std::vector<std::uint8_t> frame_iters(kPixelCount, 0);
    std::vector<bool> seen(kPixelCount, false);
    std::uint32_t done_count = 0;

    dut->rst_n = 0;
    dut->clk = 0;

    for (int i = 0; i < 20; ++i) {
        dut->clk ^= 1;
        dut->eval();
    }

    dut->rst_n = 1;

    while (done_count < kPixelCount) {
        dut->clk ^= 1;
        dut->eval();

        if ((dut->clk == 1) && dut->pix_done) {
            const std::uint32_t pix_id = dut->pix_id;
            if (pix_id < kPixelCount) {
                frame_iters[pix_id] = dut->pix_iter;
                if (!seen[pix_id]) {
                    seen[pix_id] = true;
                    ++done_count;
                }
            }
        }
    }

    std::vector<RGB> frame_pixels(kPixelCount);
    for (std::uint32_t i = 0; i < kPixelCount; ++i) {
        frame_pixels[i] = iter_to_rgb(frame_iters[i]);
    }

    std::vector<RGB> screen_pixels(kScreenW * kScreenH);
    for (std::uint32_t y = 0; y < kFrameH; ++y) {
        for (std::uint32_t x = 0; x < kFrameW; ++x) {
            const RGB pixel = frame_pixels[y * kFrameW + x];
            const std::uint32_t sx = x * 2;
            const std::uint32_t sy = y * 2;

            screen_pixels[sy * kScreenW + sx] = pixel;
            screen_pixels[sy * kScreenW + sx + 1] = pixel;
            screen_pixels[(sy + 1) * kScreenW + sx] = pixel;
            screen_pixels[(sy + 1) * kScreenW + sx + 1] = pixel;
        }
    }

    write_ppm("frame.ppm", kFrameW, kFrameH, frame_pixels);
    write_ppm("screen.ppm", kScreenW, kScreenH, screen_pixels);

    delete dut;
    return 0;
}
