#include "report.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <iomanip>
#include <limits>
#include <sstream>

namespace {

/* ============================================================================
   Formatting helpers
   ============================================================================ */

// Format a floating-point number with a fixed number of digits after the decimal point
std::string format_double(double value, int precision = 6) {
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(precision) << value;
    return oss.str();
}

// Attach a unit string like "ms" or "fps" when one is provided
std::string format_value_with_unit(const std::string& value, const std::string& unit = "") {
    if (unit.empty()) return value;
    return value + " " + unit;
}

// Write one indented "key: value" line into the report file
bool write_report_line(
    FILE* out,
    const std::string& key,
    const std::string& value,
    int indent = 0,
    const std::string& unit = ""
) {
    const std::string line =
        std::string(static_cast<std::size_t>(indent) * 4, ' ') +
        key + ": " + format_value_with_unit(value, unit) + "\n";

    // fputs returns a negative number on failure
    return std::fputs(line.c_str(), out) >= 0;
}

/* ============================================================================
   Report section writers
   ============================================================================ */

// Write the top metadata block for one run
bool write_run_metadata(FILE* out, const Params& params, const RunSummary& summary) {
    bool ok = true;

    // Record which scene and quality mode were used
    ok = ok && write_report_line(out, "mode", render_mode_name(params.mode), 1);
    ok = ok && write_report_line(out, "quality", quality_mode_name(params.quality), 1);

    // Record the image size both as a combined resolution string and as separate numbers
    ok = ok && write_report_line(out, "resolution", std::to_string(params.width) + "x" + std::to_string(params.height), 1, "pixels");
    ok = ok && write_report_line(out, "width", std::to_string(params.width), 1, "pixels");
    ok = ok && write_report_line(out, "height", std::to_string(params.height), 1, "pixels");

    // Record how many frames were in this run
    ok = ok && write_report_line(out, "frames", std::to_string(summary.frames), 1);
    return ok;
}

// Write the block that records the input parameters for the run
bool write_parameter_block(FILE* out, const Params& params) {
    bool ok = true;

    // Record the fractal and march settings
    ok = ok && write_report_line(out, "iterations", std::to_string(params.iterations), 1);
    ok = ok && write_report_line(out, "scale", format_double(params.scale), 1);
    ok = ok && write_report_line(out, "min_radius", format_double(params.min_radius), 1);
    ok = ok && write_report_line(out, "fixed_radius", format_double(params.fixed_radius), 1);
    ok = ok && write_report_line(out, "fold_limit", format_double(params.fold_limit), 1);
    ok = ok && write_report_line(out, "epsilon", format_double(params.epsilon), 1);
    ok = ok && write_report_line(out, "max_distance", format_double(params.max_distance), 1);
    ok = ok && write_report_line(out, "max_steps", std::to_string(params.max_steps), 1);
    ok = ok && write_report_line(out, "fov_degrees", format_double(params.fov_degrees), 1, "degrees");

    // Record the camera pose used for the run
    ok = ok && write_report_line(out, "yaw", format_double(params.yaw), 1, "radians");
    ok = ok && write_report_line(out, "pitch", format_double(params.pitch), 1, "radians");
    ok = ok && write_report_line(out, "cam_x", format_double(params.cam_pos.x), 1);
    ok = ok && write_report_line(out, "cam_y", format_double(params.cam_pos.y), 1);
    ok = ok && write_report_line(out, "cam_z", format_double(params.cam_pos.z), 1);
    return ok;
}

// Write the aggregate summary values that describe the whole run
bool write_summary_block(FILE* out, const RunSummary& summary) {
    bool ok = true;

    // Record time and throughput measures
    ok = ok && write_report_line(out, "avg_frame_ms", format_double(summary.avg_frame_ms, 3), 1, "ms");
    ok = ok && write_report_line(out, "min_frame_ms", format_double(summary.min_frame_ms, 3), 1, "ms");
    ok = ok && write_report_line(out, "max_frame_ms", format_double(summary.max_frame_ms, 3), 1, "ms");
    ok = ok && write_report_line(out, "frame_stddev_ms", format_double(summary.frame_stddev_ms, 3), 1, "ms");
    ok = ok && write_report_line(out, "avg_fps", format_double(summary.avg_fps, 3), 1, "fps");
    ok = ok && write_report_line(out, "avg_pixels_per_second", format_double(summary.avg_pixels_per_second, 3), 1, "pixels_per_second");
    ok = ok && write_report_line(out, "avg_steps_per_pixel", format_double(summary.avg_steps, 3), 1, "steps_per_pixel");

    // Record hit ratios and raw workload totals
    ok = ok && write_report_line(out, "avg_hit_ratio", format_double(summary.avg_hit_ratio, 6), 1);
    ok = ok && write_report_line(out, "avg_hit_ratio_percent", format_double(summary.avg_hit_ratio * 100.0, 3), 1, "percent");
    ok = ok && write_report_line(out, "total_pixels_per_frame", std::to_string(summary.total_pixels_per_frame), 1, "pixels");
    ok = ok && write_report_line(out, "total_pixels_across_run", std::to_string(summary.total_pixels_all), 1, "pixels");
    ok = ok && write_report_line(out, "avg_total_steps_per_frame", format_double(summary.avg_total_steps_per_frame, 3), 1, "steps");
    ok = ok && write_report_line(out, "avg_hit_pixels_per_frame", format_double(summary.avg_hit_pixels_per_frame, 3), 1, "pixels");
    return ok;
}

// Write the nested block for one individual frame
bool write_frame_block(FILE* out, std::size_t frame_index, const FrameStats& frame) {
    const std::string heading = "    frame_" + std::to_string(frame_index) + ":\n";
    bool ok = std::fputs(heading.c_str(), out) >= 0;

    // Record the metrics collected for this one frame
    ok = ok && write_report_line(out, "frame_ms", format_double(frame.frame_ms, 3), 2, "ms");
    ok = ok && write_report_line(out, "fps", format_double(frame.fps, 3), 2, "fps");
    ok = ok && write_report_line(out, "pixels_per_second", format_double(frame.pixels_per_second, 3), 2, "pixels_per_second");
    ok = ok && write_report_line(out, "avg_steps_per_pixel", format_double(frame.avg_steps, 3), 2, "steps_per_pixel");
    ok = ok && write_report_line(out, "hit_ratio", format_double(frame.hit_ratio, 6), 2);
    ok = ok && write_report_line(out, "hit_ratio_percent", format_double(frame.hit_ratio * 100.0, 3), 2, "percent");
    ok = ok && write_report_line(out, "total_pixels", std::to_string(frame.total_pixels), 2, "pixels");
    ok = ok && write_report_line(out, "total_steps", std::to_string(frame.total_steps), 2, "steps");
    ok = ok && write_report_line(out, "hit_pixels", std::to_string(frame.hit_pixels), 2, "pixels");
    return ok;
}

/* ============================================================================
   File bookkeeping helpers
   ============================================================================ */

// Check whether the report file already exists and has any bytes in it
bool file_has_content(const std::string& path) {
    FILE* in = std::fopen(path.c_str(), "rb");
    if (!in) return false;

    // Seek to the end and check whether the file length is greater than zero
    const bool ok =
        std::fseek(in, 0, SEEK_END) == 0 &&
        std::ftell(in) > 0;

    std::fclose(in);
    return ok;
}

// Find the next run number by scanning existing "run_N:" headings in the file
int next_run_id(const std::string& path) {
    FILE* in = std::fopen(path.c_str(), "r");
    if (!in) return 1;

    // Use a fixed-size line buffer for simple text scanning
    char buffer[1024];
    int max_run_id = 0;
    while (std::fgets(buffer, static_cast<int>(sizeof(buffer)), in)) {
        const std::string line(buffer);

        // Ignore lines that do not begin with a run heading
        if (line.rfind("run_", 0) != 0) continue;

        const std::size_t colon = line.find(':');
        if (colon == std::string::npos || colon <= 4) continue;

        try {
            // Read the number between "run_" and ":"
            const int run_id = std::stoi(line.substr(4, colon - 4));
            max_run_id = std::max(max_run_id, run_id);
        } catch (...) {
            // Ignore malformed lines and keep scanning
        }
    }

    std::fclose(in);
    return max_run_id + 1;
}

} // namespace

/* ============================================================================
   Summary generation
   ============================================================================ */

// Combine the per-frame statistics into one whole-run summary
RunSummary summarize_frames(const std::vector<FrameStats>& frames) {
    RunSummary summary;

    // If there are no frames there is nothing to aggregate
    if (frames.empty()) return summary;

    // Seed the summary with known values before accumulation begins
    summary.frames = static_cast<int>(frames.size());
    summary.min_frame_ms = std::numeric_limits<double>::max();
    summary.max_frame_ms = 0.0;
    summary.total_pixels_per_frame = frames.front().total_pixels;

    // Sum the raw totals across every frame
    for (const FrameStats& frame : frames) {
        summary.total_ms += frame.frame_ms;
        summary.min_frame_ms = std::min(summary.min_frame_ms, frame.frame_ms);
        summary.max_frame_ms = std::max(summary.max_frame_ms, frame.frame_ms);
        summary.total_pixels_all += frame.total_pixels;
        summary.total_steps_all += frame.total_steps;
        summary.hit_pixels_all += frame.hit_pixels;
    }

    // Turn the total time into an average frame time
    summary.avg_frame_ms = summary.total_ms / static_cast<double>(summary.frames);

    // Compute the frame-time variance so we can derive the standard deviation
    double variance = 0.0;
    for (const FrameStats& frame : frames) {
        const double delta = frame.frame_ms - summary.avg_frame_ms;
        variance += delta * delta;
    }

    // Derive the remaining summary metrics from the accumulated totals
    summary.frame_stddev_ms = std::sqrt(variance / static_cast<double>(summary.frames));
    summary.avg_fps = 1000.0 / summary.avg_frame_ms;
    summary.avg_pixels_per_second =
        static_cast<double>(summary.total_pixels_all) / (summary.total_ms / 1000.0);

    // Only divide when there were actually pixels rendered
    if (summary.total_pixels_all > 0) {
        summary.avg_steps =
            static_cast<double>(summary.total_steps_all) / static_cast<double>(summary.total_pixels_all);
        summary.avg_hit_ratio =
            static_cast<double>(summary.hit_pixels_all) / static_cast<double>(summary.total_pixels_all);
    }

    // Also expose the average raw totals per frame
    summary.avg_total_steps_per_frame =
        static_cast<double>(summary.total_steps_all) / static_cast<double>(summary.frames);
    summary.avg_hit_pixels_per_frame =
        static_cast<double>(summary.hit_pixels_all) / static_cast<double>(summary.frames);

    return summary;
}

/* ============================================================================
   Report writer
   ============================================================================ */

// Append one readable benchmark block to the report file
bool append_text_report(
    const std::string& path,
    const Params& params,
    const std::vector<FrameStats>& frames,
    const RunSummary& summary
) {
    // Figure out whether the file already has earlier runs inside it
    const bool has_content = file_has_content(path);

    // Choose the next run number to avoid overwriting earlier blocks
    const int run_id = next_run_id(path);

    // Open the report file in append mode
    FILE* out = std::fopen(path.c_str(), "a");
    if (!out) return false;

    // ok accumulates whether every write succeeded
    bool ok = true;
    if (has_content) {
        // Separate this run from the previous run with a blank line
        ok = ok && std::fputs("\n", out) >= 0;
    }

    // Write the top run heading
    const std::string run_heading = "run_" + std::to_string(run_id) + ":\n";
    ok = ok && std::fputs(run_heading.c_str(), out) >= 0;

    // Write the metadata, parameter and summary blocks
    ok = ok && write_run_metadata(out, params, summary);

    ok = ok && std::fputs("\n", out) >= 0;
    ok = ok && write_parameter_block(out, params);

    ok = ok && std::fputs("\n", out) >= 0;
    ok = ok && write_summary_block(out, summary);

    // Write one nested block per frame
    ok = ok && std::fputs("\n", out) >= 0;
    for (std::size_t i = 0; i < frames.size(); ++i) {
        ok = ok && write_frame_block(out, i, frames[i]);
    }

    // fclose both flushes the file and releases the handle
    return std::fclose(out) == 0 && ok;
}
