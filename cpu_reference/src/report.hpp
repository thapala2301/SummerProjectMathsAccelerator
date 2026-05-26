#pragma once

/* ============================================================================
   Report generation interface
   ============================================================================ */

// This header defines the summary data and report-writing functions
// Splitting them out keeps main.cpp focused on program flow instead of text formatting

#include <string>
#include <vector>

#include "renderer.hpp"

// RunSummary stores measurements aggregated across every frame in one benchmark run
struct RunSummary {
    // Number of frames that were included in the run
    int frames = 0;

    // Total and aggregate timing values
    double total_ms = 0.0;
    double avg_frame_ms = 0.0;
    double min_frame_ms = 0.0;
    double max_frame_ms = 0.0;
    double frame_stddev_ms = 0.0;

    // Aggregate throughput and workload values
    double avg_fps = 0.0;
    double avg_pixels_per_second = 0.0;
    double avg_steps = 0.0;
    double avg_hit_ratio = 0.0;

    // Whole-run raw totals used to compute exact derived metrics
    long long total_pixels_per_frame = 0;
    long long total_pixels_all = 0;
    long long total_steps_all = 0;
    long long hit_pixels_all = 0;

    // Averages of the raw totals on a per-frame basis
    double avg_total_steps_per_frame = 0.0;
    double avg_hit_pixels_per_frame = 0.0;
};

// Combine many per-frame stats objects into one run summary
RunSummary summarize_frames(const std::vector<FrameStats>& frames);

// Append one readable benchmark report block to a text file
bool append_text_report(
    const std::string& path,
    const Params& params,
    const std::vector<FrameStats>& frames,
    const RunSummary& summary
);
