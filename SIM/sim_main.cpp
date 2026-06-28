#include "Vsim_top.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {

constexpr std::uint32_t kFrameW = 512;
constexpr std::uint32_t kFrameH = 300;
constexpr std::uint32_t kScreenW = 1024;
constexpr std::uint32_t kScreenH = 600;
constexpr std::uint32_t kBytesPerPixel = 4;
constexpr std::uint32_t kScreenBytes = kScreenW * kScreenH * kBytesPerPixel;
constexpr std::uint64_t kMaxCycles = 100000000ULL;

struct RGB {
    std::uint8_t r;
    std::uint8_t g;
    std::uint8_t b;
};

RGB word_to_rgb(std::uint32_t word) {
    return {
        static_cast<std::uint8_t>((word >> 16) & 0xff),
        static_cast<std::uint8_t>((word >> 8) & 0xff),
        static_cast<std::uint8_t>(word & 0xff)
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

void apply_write(std::vector<std::uint32_t>& ddr, std::uint32_t addr,
                 std::uint64_t data, std::uint64_t& write_count,
                 std::uint64_t& out_of_range_count) {
    if ((addr & 7U) != 0 || (addr + 8U) > kScreenBytes) {
        ++out_of_range_count;
        return;
    }

    const std::uint32_t word_index = addr / kBytesPerPixel;
    ddr[word_index] = static_cast<std::uint32_t>(data & 0xffffffffULL);
    ddr[word_index + 1] = static_cast<std::uint32_t>((data >> 32) & 0xffffffffULL);
    ++write_count;
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vsim_top* dut = new Vsim_top;
    std::vector<std::uint32_t> ddr(kScreenW * kScreenH, 0);

    std::uint64_t cycles = 0;
    std::uint64_t write_count = 0;
    std::uint64_t out_of_range_count = 0;
    bool response_pending = false;

    dut->clk = 0;
    dut->rst_n = 0;
    dut->axi_awready = 1;
    dut->axi_wready = 1;
    dut->axi_bvalid = 0;

    auto tick = [&]() {
        dut->clk = 0;
        dut->eval();

        const bool accept_write = dut->axi_awvalid && dut->axi_awready &&
                                  dut->axi_wvalid && dut->axi_wready;
        const std::uint32_t accepted_addr = dut->axi_awaddr;
        const std::uint64_t accepted_data = dut->axi_wdata;

        dut->axi_bvalid = response_pending ? 1 : 0;
        dut->clk = 1;
        dut->eval();

        if (accept_write) {
            apply_write(ddr, accepted_addr, accepted_data, write_count, out_of_range_count);
        }

        response_pending = accept_write;
        ++cycles;
    };

    for (int i = 0; i < 20; ++i) {
        tick();
    }

    dut->rst_n = 1;

    while (!dut->frame_done && cycles < kMaxCycles) {
        tick();
    }

    if (!dut->frame_done) {
        std::fprintf(stderr, "Timed out after %llu cycles\n",
                     static_cast<unsigned long long>(cycles));
        delete dut;
        return 1;
    }

    std::vector<RGB> frame_pixels(kFrameW * kFrameH);
    for (std::uint32_t y = 0; y < kFrameH; ++y) {
        for (std::uint32_t x = 0; x < kFrameW; ++x) {
            const std::uint32_t screen_x = x * 2U;
            const std::uint32_t screen_y = y * 2U;
            frame_pixels[y * kFrameW + x] =
                word_to_rgb(ddr[screen_y * kScreenW + screen_x]);
        }
    }

    std::vector<RGB> screen_pixels(kScreenW * kScreenH);
    for (std::uint32_t y = 0; y < kScreenH; ++y) {
        for (std::uint32_t x = 0; x < kScreenW; ++x) {
            screen_pixels[y * kScreenW + x] = word_to_rgb(ddr[y * kScreenW + x]);
        }
    }

    write_ppm("frame.ppm", kFrameW, kFrameH, frame_pixels);
    write_ppm("screen.ppm", kScreenW, kScreenH, screen_pixels);

    std::printf("cycles            = %llu\n", static_cast<unsigned long long>(cycles));
    std::printf("axi_64bit_writes  = %llu\n", static_cast<unsigned long long>(write_count));
    std::printf("out_of_range      = %llu\n", static_cast<unsigned long long>(out_of_range_count));
    std::printf("expected_writes   = %u\n", kFrameW * kFrameH * 2U);

    delete dut;
    return 0;
}