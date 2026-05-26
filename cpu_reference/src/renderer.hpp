#pragma once

/* ============================================================================
   Renderer interface
   ============================================================================ */

// This header exposes the types and functions other files need from the renderer
// The heavy implementation details live in renderer.cpp

#include <cstdint>
#include <vector>

#include "config.hpp"
#include "vec3.hpp"

// FrameStats stores the numeric measurements collected while rendering one frame
struct FrameStats {
    // How long the frame took to render in milliseconds
    double frame_ms = 0.0;

    // Frames per second derived from frame_ms
    double fps = 0.0;

    // Pixel throughput derived from frame time and pixel count
    double pixels_per_second = 0.0;

    // Average number of march steps used per pixel
    double avg_steps = 0.0;

    // Fraction of rays that hit scene geometry before giving up
    double hit_ratio = 0.0;

    // Raw totals kept for exact report calculations later
    long long total_pixels = 0;
    long long total_steps = 0;
    long long hit_pixels = 0;
};

// RenderOutput bundles the image and stats produced by one render_frame call
struct RenderOutput {
    // Final image bytes stored as packed 8-bit RGB values
    std::vector<std::uint8_t> rgb;

    // Statistics collected while producing the rgb image
    FrameStats stats;
};

// Build the camera forward direction from yaw and pitch
Vec3 camera_forward(double yaw, double pitch);

// Build the camera right direction from yaw
Vec3 camera_right(double yaw);

// Build the camera up direction from the other camera basis vectors
Vec3 camera_up(double yaw, double pitch);

// Render one complete frame and return both its image and its statistics
RenderOutput render_frame(const Params& params);

// Save a packed RGB buffer as a binary PPM image file
bool save_ppm(const std::string& path, int width, int height, const std::vector<std::uint8_t>& rgb);
