#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

#include "renderer.hpp"
#include "report.hpp"

namespace {

/* ============================================================================
   Help and parsing helpers
   ============================================================================ */

// Print the command-line help text
void print_help() {
    std::cout <<
R"(cpu_raymarch - CPU Mandelbox/SDF ray marching benchmark

Options:
  --mode mandelbox|sphere|cube
  --quality base|full
  --width N
  --height N
  --frames N
  --iterations N
  --scale X
  --min-radius X
  --fixed-radius X
  --fold-limit X
  --epsilon X
  --max-distance X
  --max-steps N
  --fov X
  --cam-x X --cam-y X --cam-z X
  --yaw X          yaw in radians
  --pitch X        pitch in radians
  --out path.ppm
  --csv path.txt   human-readable benchmark report (legacy flag name)
  --help

Examples:
  ./cpu_raymarch --mode mandelbox --quality base --width 320 --height 180 --frames 3
  ./cpu_raymarch --mode mandelbox --quality full --width 320 --height 180 --frames 1 --out out.ppm
)";
}

// Check that there is still one more command-line token available after the current one
bool has_arg(int index, int argc) {
    return index + 1 < argc;
}

// Convert a C string from argv into a double
double parse_double(const char* value) {
    return std::stod(std::string(value));
}

// Convert a C string from argv into an int
int parse_int(const char* value) {
    return std::stoi(std::string(value));
}

// Convert the text after --mode into the RenderMode enum
bool parse_render_mode(const std::string& value, RenderMode& mode) {
    if (value == "sphere") {
        mode = RenderMode::Sphere;
        return true;
    }
    if (value == "cube") {
        mode = RenderMode::Cube;
        return true;
    }
    if (value == "mandelbox") {
        mode = RenderMode::Mandelbox;
        return true;
    }
    return false;
}

// Convert the text after --quality into the QualityMode enum
bool parse_quality_mode(const std::string& value, QualityMode& quality) {
    if (value == "base") {
        quality = QualityMode::Base;
        return true;
    }
    if (value == "full") {
        quality = QualityMode::Full;
        return true;
    }
    return false;
}

// Return a detailed result from command-line parsing
enum class ParseStatus {
    Success,
    HelpShown,
    Failure
};

// Walk through argv and fill the Params struct
ParseStatus parse_command_line(int argc, char** argv, Params& params) {
    // Start at 1 because argv[0] is the program name
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];

        // Handle --help immediately and stop further parsing
        if (arg == "--help") {
            print_help();
            return ParseStatus::HelpShown;
        }

        // Parse the named mode option
        if (arg == "--mode" && has_arg(i, argc)) {
            if (!parse_render_mode(argv[++i], params.mode)) {
                std::cerr << "Unknown mode: " << argv[i] << "\n";
                return ParseStatus::Failure;
            }
            continue;
        }

        // Parse the named quality option
        if (arg == "--quality" && has_arg(i, argc)) {
            if (!parse_quality_mode(argv[++i], params.quality)) {
                std::cerr << "Unknown quality: " << argv[i] << "\n";
                return ParseStatus::Failure;
            }
            continue;
        }

        // The remaining flags are direct assignments into Params
        // Keeping them together makes the command-line surface easy to scan
        if (arg == "--width" && has_arg(i, argc)) params.width = parse_int(argv[++i]);
        else if (arg == "--height" && has_arg(i, argc)) params.height = parse_int(argv[++i]);
        else if (arg == "--frames" && has_arg(i, argc)) params.frames = parse_int(argv[++i]);
        else if (arg == "--iterations" && has_arg(i, argc)) params.iterations = parse_int(argv[++i]);
        else if (arg == "--scale" && has_arg(i, argc)) params.scale = parse_double(argv[++i]);
        else if (arg == "--min-radius" && has_arg(i, argc)) params.min_radius = parse_double(argv[++i]);
        else if (arg == "--fixed-radius" && has_arg(i, argc)) params.fixed_radius = parse_double(argv[++i]);
        else if (arg == "--fold-limit" && has_arg(i, argc)) params.fold_limit = parse_double(argv[++i]);
        else if (arg == "--epsilon" && has_arg(i, argc)) params.epsilon = parse_double(argv[++i]);
        else if (arg == "--max-distance" && has_arg(i, argc)) params.max_distance = parse_double(argv[++i]);
        else if (arg == "--max-steps" && has_arg(i, argc)) params.max_steps = parse_int(argv[++i]);
        else if (arg == "--fov" && has_arg(i, argc)) params.fov_degrees = parse_double(argv[++i]);
        else if (arg == "--yaw" && has_arg(i, argc)) params.yaw = parse_double(argv[++i]);
        else if (arg == "--pitch" && has_arg(i, argc)) params.pitch = parse_double(argv[++i]);
        else if (arg == "--cam-x" && has_arg(i, argc)) params.cam_pos.x = parse_double(argv[++i]);
        else if (arg == "--cam-y" && has_arg(i, argc)) params.cam_pos.y = parse_double(argv[++i]);
        else if (arg == "--cam-z" && has_arg(i, argc)) params.cam_pos.z = parse_double(argv[++i]);
        else if (arg == "--out" && has_arg(i, argc)) params.output_ppm = argv[++i];
        else if (arg == "--csv" && has_arg(i, argc)) params.output_report_path = argv[++i];
        else {
            // If a flag is unknown or missing its value explain that and stop
            std::cerr << "Unknown or incomplete argument: " << arg << "\n";
            print_help();
            return ParseStatus::Failure;
        }
    }

    // frames must be positive because rendering zero or negative frames does not make sense
    if (params.frames < 1) {
        std::cerr << "frames must be >= 1\n";
        return ParseStatus::Failure;
    }

    return ParseStatus::Success;
}

/* ============================================================================
   Console output helpers
   ============================================================================ */

// Print a short one-line description of the run before the frame loop starts
void print_run_header(const Params& params) {
    std::cout << "CPU ray marching benchmark\n";
    std::cout << "mode=" << render_mode_name(params.mode)
              << " quality=" << quality_mode_name(params.quality)
              << " resolution=" << params.width << "x" << params.height
              << " frames=" << params.frames << "\n";
}

// Print the timing and workload summary for one frame
void print_frame_summary(int frame_index, const FrameStats& stats) {
    std::cout << "frame " << frame_index
              << ": " << std::fixed << std::setprecision(3)
              << stats.frame_ms << " ms, "
              << stats.fps << " fps, "
              << "avg_steps=" << stats.avg_steps
              << ", hit_ratio=" << (stats.hit_ratio * 100.0) << "%\n";
}

// Print the summary values aggregated across the entire run
void print_run_summary(const RunSummary& summary) {
    std::cout << "\nSummary\n";
    std::cout << "average_frame_ms=" << std::fixed << std::setprecision(3) << summary.avg_frame_ms << "\n";
    std::cout << "min_frame_ms=" << summary.min_frame_ms << "\n";
    std::cout << "max_frame_ms=" << summary.max_frame_ms << "\n";
    std::cout << "frame_stddev_ms=" << summary.frame_stddev_ms << "\n";
    std::cout << "average_fps=" << summary.avg_fps << "\n";
    std::cout << "average_pixels_per_second=" << summary.avg_pixels_per_second << "\n";
    std::cout << "average_steps_per_pixel=" << summary.avg_steps << "\n";
    std::cout << "average_hit_ratio_percent=" << (summary.avg_hit_ratio * 100.0) << "\n";
}

} // namespace

/* ============================================================================
   Program entry point
   ============================================================================ */

int main(int argc, char** argv) {
    // Create a Params struct filled with its default values
    Params params;

    // Parse the command-line arguments into params
    const ParseStatus parse_status = parse_command_line(argc, argv, params);
    if (parse_status == ParseStatus::HelpShown) return 0;
    if (parse_status == ParseStatus::Failure) return 1;

    // Collect per-frame stats so we can compute a whole-run summary afterward
    std::vector<FrameStats> frame_stats;

    // Keep the last frame's image because that is what optional PPM output should save
    RenderOutput last_frame;

    print_run_header(params);

    for (int frame_index = 0; frame_index < params.frames; ++frame_index) {
        // Render one complete frame
        // Each frame is independent so the benchmark is deterministic and easy to compare
        last_frame = render_frame(params);

        // Store the frame statistics for later aggregation
        frame_stats.push_back(last_frame.stats);

        // Print a live summary line so the user can see progress
        print_frame_summary(frame_index, last_frame.stats);
    }

    // Collapse all per-frame stats into one overall summary
    const RunSummary summary = summarize_frames(frame_stats);
    print_run_summary(summary);

    // If the user asked for an image, save the last rendered frame as a PPM file
    if (!params.output_ppm.empty()) {
        if (save_ppm(params.output_ppm, params.width, params.height, last_frame.rgb)) {
            std::cout << "saved " << params.output_ppm << "\n";
        } else {
            std::cerr << "failed to save " << params.output_ppm << "\n";
            return 1;
        }
    }

    // If the user asked for a report, append the run summary to the report file
    if (!params.output_report_path.empty()) {
        if (append_text_report(params.output_report_path, params, frame_stats, summary)) {
            std::cout << "appended benchmark report " << params.output_report_path << "\n";
        } else {
            std::cerr << "failed to append benchmark report " << params.output_report_path << "\n";
            return 1;
        }
    }

    // Returning 0 tells the operating system the program finished successfully
    return 0;
}
