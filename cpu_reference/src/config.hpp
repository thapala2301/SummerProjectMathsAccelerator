#pragma once

/* ============================================================================
   Shared configuration types
   ============================================================================ */

// This header defines the small pieces of shared configuration that multiple .cpp files need
// Putting them here means the command-line parser, renderer, SDF code and report writer all
// agree on the same types and field names

#include <string>

#include "vec3.hpp"

/* ============================================================================
   Render mode enums
   ============================================================================ */

// Choose which scene the renderer should trace against
enum class RenderMode {
    Mandelbox = 0,
    Sphere = 1,
    Cube = 2
};

// Turn the enum back into the text used on the command line and in reports
inline const char* render_mode_name(RenderMode mode) {
    if (mode == RenderMode::Sphere) return "sphere";
    if (mode == RenderMode::Cube) return "cube";
    return "mandelbox";
}

// Choose whether to do simple benchmark colouring or the fuller shading path
enum class QualityMode {
    Base,
    Full
};

// Turn the quality enum back into the user-facing text form
inline const char* quality_mode_name(QualityMode quality) {
    return quality == QualityMode::Full ? "full" : "base";
}

/* ============================================================================
   Runtime parameter bundle
   ============================================================================ */

// Collect every user-configurable runtime option into one struct
// main.cpp fills this from the command line and the renderer reads it as input
struct Params {
    // Output image size and how many frames to render
    int width = 320;
    int height = 180;
    int frames = 1;

    // Which scene to render and which shading mode to use
    RenderMode mode = RenderMode::Mandelbox;
    QualityMode quality = QualityMode::Base;

    // Mandelbox controls and ray-march limits
    int iterations = 13;
    double scale = -1.78;
    double min_radius = 0.5;
    double fixed_radius = 1.0;
    double fold_limit = 1.0;
    double epsilon = 0.0015;
    double max_distance = 80.0;
    int max_steps = 160;
    double fov_degrees = 60.0;

    // Camera position and orientation
    Vec3 cam_pos = Vec3{0.0, 0.15, 4.5};
    double yaw = 0.0;
    double pitch = 0.0;

    // Optional output file paths
    // output_report_path still uses the legacy --csv flag name for compatibility
    std::string output_ppm;
    std::string output_report_path;
};
