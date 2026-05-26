#include "renderer.hpp"
#include "sdf.hpp"

#include <chrono>
#include <cstdio>
#include <iostream>

namespace {

/* ============================================================================
   Local constants
   ============================================================================ */

// Store pi once for angle conversion
static constexpr double PI = 3.14159265358979323846;

/* ============================================================================
   Small local helpers
   ============================================================================ */

// Convert degrees into radians because std::tan expects radians
double radians(double degrees) {
    return degrees * PI / 180.0;
}

// Estimate a surface normal by sampling the distance field around p
// The returned vector points in the direction the distance increases most quickly
Vec3 estimate_normal(const Vec3& p, const Params& params) {
    // Pick a small sample spacing based on the surface hit threshold
    const double e = std::max(params.epsilon * 2.0, 0.00035);

    // Sample the scene on opposite sides of the point along each axis
    const double dx = map_scene(p + Vec3{e, 0.0, 0.0}, params) -
                      map_scene(p - Vec3{e, 0.0, 0.0}, params);

    const double dy = map_scene(p + Vec3{0.0, e, 0.0}, params) -
                      map_scene(p - Vec3{0.0, e, 0.0}, params);

    const double dz = map_scene(p + Vec3{0.0, 0.0, e}, params) -
                      map_scene(p - Vec3{0.0, 0.0, e}, params);

    // If the samples produced invalid numbers return a safe default normal
    if (!std::isfinite(dx) || !std::isfinite(dy) || !std::isfinite(dz)) {
        return Vec3{0.0, 1.0, 0.0};
    }

    // Turn the derivative estimates into a unit-length normal
    return normalise(Vec3{dx, dy, dz});
}

// March a second ray toward the light to estimate how shadowed the hit point is
double soft_shadow(const Vec3& ro, const Vec3& rd, double mint, double maxt, const Params& params) {
    // Start fully lit and reduce the value if blockers appear along the light ray
    double result = 1.0;
    double t = mint;

    for (int i = 0; i < 80; ++i) {
        if (t >= maxt) break;
        const double h = map_scene(ro + rd * t, params);

        // A very small distance means the light ray hit geometry
        if (h < 0.001) return 0.05;

        // Smaller distances mean the light is more occluded
        result = std::min(result, 12.0 * h / t);

        // March forward using a clamped distance so the loop stays stable
        t += clamp_double(h, 0.015, 0.18);
    }

    return clamp_double(result, 0.05, 1.0);
}

// Estimate ambient occlusion by probing the scene a short distance along the normal
double ambient_occlusion(const Vec3& p, const Vec3& n, const Params& params) {
    double occ = 0.0;
    double sca = 1.0;

    for (int i = 1; i <= 5; ++i) {
        // Sample farther away with each iteration
        const double h = 0.04 * static_cast<double>(i);
        const double d = map_scene(p + n * h, params);

        // If nearby geometry appears quickly the point is more occluded
        occ += (h - d) * sca;

        // Reduce the weight of farther samples
        sca *= 0.72;
    }

    // Convert the accumulated occlusion into a 0..1 brightness factor
    return clamp_double(1.0 - 2.0 * occ, 0.0, 1.0);
}

// Return the background colour for rays that miss all geometry
// The CPU reference keeps this intentionally simple because the main benchmark target is the march loop
Vec3 background(const Vec3& rd) {
    // Use the ray's vertical direction to blend between horizon and sky
    const double t = clamp_double(rd.y * 0.5 + 0.5, 0.0, 1.0);
    const Vec3 top{0.62, 0.70, 0.82};
    const Vec3 bottom{0.18, 0.20, 0.24};
    return mix_vec(bottom, top, t);
}

// Compute the more expensive full shading path used for visual reference output
Vec3 shade_full(const Vec3& rd, const Vec3& p, double travel, int steps, const Params& params) {
    // Build the local lighting frame at the hit point
    const Vec3 n = estimate_normal(p, params);
    const Vec3 light_dir = normalise(Vec3{0.7, 1.0, 0.45});
    const Vec3 half_dir = normalise(light_dir - rd);

    // Compute the main lighting terms
    const double diff = std::max(dot(n, light_dir), 0.0);
    const double fresnel = std::pow(1.0 - std::max(dot(n, rd * -1.0), 0.0), 3.0);
    const double spec = std::pow(std::max(dot(n, half_dir), 0.0), 64.0);
    const double shadow = soft_shadow(p + n * 0.01, light_dir, 0.03, 6.0, params);
    const double ao = ambient_occlusion(p, n, params);

    // Choose a neutral base material colour
    Vec3 base{0.58, 0.58, 0.56};
    if (params.mode == RenderMode::Mandelbox) {
        // Add subtle bands on the Mandelbox so its structure is easier to read
        const double bands = 0.5 + 0.5 * std::sin(8.0 * length(p) + 0.35 * static_cast<double>(steps));
        base = mix_vec(Vec3{0.46, 0.46, 0.44}, Vec3{0.74, 0.73, 0.68}, bands * 0.45);
    }

    // Combine diffuse light, specular highlight and fresnel rim lighting
    Vec3 col = base * ((0.18 + 0.82 * diff * shadow) * ao);
    col = col + Vec3{1.0, 1.0, 1.0} * (spec * shadow * 0.55);
    col = col + Vec3{0.78, 0.86, 1.0} * (fresnel * 0.22);

    // Fade distant geometry into the background
    const double fog = 1.0 - std::exp(-0.035 * travel * travel);
    col = mix_vec(col, background(rd), fog);

    // Replace any invalid numbers with safe fallback values before returning
    return Vec3{
        finite_or(col.x),
        finite_or(col.y),
        finite_or(col.z)
    };
}

// Compute the cheaper benchmark-focused shading path
// This keeps most of the work concentrated in the primary march loop
Vec3 shade_base(bool hit, const Vec3& rd, double travel, int steps, const Params& params) {
    // Misses just show the background
    if (!hit) return background(rd);

    // Convert travel distance and step count into simple greyscale factors
    const double depth_factor = 1.0 - clamp_double(travel / params.max_distance, 0.0, 1.0);
    const double step_factor = 1.0 - clamp_double(static_cast<double>(steps) / static_cast<double>(params.max_steps), 0.0, 1.0);

    // Blend those factors into a brightness value
    double v = 0.25 + 0.55 * depth_factor + 0.20 * step_factor;
    if (params.mode == RenderMode::Mandelbox) {
        // Add a small variation for the Mandelbox to make structure a bit easier to see
        v *= 0.85 + 0.15 * std::sin(0.6 * static_cast<double>(steps));
    }

    // Return a greyscale colour
    return Vec3{v, v, v};
}

} // namespace

/* ============================================================================
   Camera basis construction
   ============================================================================ */

// Build the camera forward direction from yaw and pitch
Vec3 camera_forward(double yaw, double pitch) {
    const double cy = std::cos(yaw);
    const double sy = std::sin(yaw);
    const double cp = std::cos(pitch);
    const double sp = std::sin(pitch);

    return normalise(Vec3{sy * cp, sp, -cy * cp});
}

// Build the camera right direction from yaw
Vec3 camera_right(double yaw) {
    const double cy = std::cos(yaw);
    const double sy = std::sin(yaw);
    return normalise(Vec3{cy, 0.0, sy});
}

// Build the camera up direction from the other basis vectors
Vec3 camera_up(double yaw, double pitch) {
    const Vec3 f = camera_forward(yaw, pitch);
    const Vec3 r = camera_right(yaw);
    return normalise(cross(r, f));
}

/* ============================================================================
   Frame renderer
   ============================================================================ */

// Render one full frame from the current parameters
RenderOutput render_frame(const Params& params) {
    // Create the output struct that will hold both image bytes and stats
    RenderOutput out;

    // Allocate three bytes per pixel for RGB output
    out.rgb.resize(static_cast<std::size_t>(params.width) * static_cast<std::size_t>(params.height) * 3);

    // Start timing the frame
    const auto start = std::chrono::high_resolution_clock::now();

    // Build the camera basis once per frame instead of once per pixel
    const Vec3 ro = params.cam_pos;
    const Vec3 fwd = camera_forward(params.yaw, params.pitch);
    const Vec3 right = camera_right(params.yaw);
    const Vec3 up = camera_up(params.yaw, params.pitch);
    const double fov_scale = std::tan(radians(params.fov_degrees) * 0.5);

    // These counters accumulate the frame-level statistics
    long long total_steps = 0;
    long long hit_pixels = 0;
    const long long total_pixels = static_cast<long long>(params.width) * static_cast<long long>(params.height);

    // Loop over every output pixel
    for (int y = 0; y < params.height; ++y) {
        for (int x = 0; x < params.width; ++x) {
            // Convert the pixel coordinates into the same centred UV coordinates used by the shader
            // The +0.5 samples at pixel centres instead of pixel corners
            const double uv_x =
                ((static_cast<double>(x) + 0.5) * 2.0 - static_cast<double>(params.width)) /
                static_cast<double>(params.height);

            const double uv_y =
                ((static_cast<double>(params.height - 1 - y) + 0.5) * 2.0 - static_cast<double>(params.height)) /
                static_cast<double>(params.height);

            // Build the ray direction for this pixel in world space
            const Vec3 rd = normalise(right * (uv_x * fov_scale) + up * (uv_y * fov_scale) + fwd);

            // t stores how far along the ray we have marched so far
            double t = 0.0;

            // hit records whether the primary ray reached geometry
            bool hit = false;

            // steps_taken records the final step count for this pixel
            int steps_taken = 0;

            // March along the ray until we hit the surface or exceed the limits
            for (int i = 0; i < params.max_steps; ++i) {
                // Compute the world-space sample point at distance t
                const Vec3 p = ro + rd * t;

                // Query the distance to the active scene
                const double d = map_scene(p, params);
                steps_taken = i;

                // If the distance function produced nonsense bail out safely
                if (!std::isfinite(d)) {
                    hit = false;
                    t = params.max_distance;
                    break;
                }

                // A small enough distance counts as a hit
                if (d < params.epsilon) {
                    hit = true;
                    break;
                }

                // Advance along the ray by most of the safe distance
                t += std::max(d * 0.85, 0.0008);

                // Stop if we have marched too far away
                if (t > params.max_distance) break;
            }

            // Choose the shading path for this pixel
            Vec3 col;
            if (params.quality == QualityMode::Full && hit) {
                col = shade_full(rd, ro + rd * t, t, steps_taken, params);
            } else {
                col = shade_base(hit, rd, t, steps_taken, params);
            }

            // In full mode misses still use the background
            if (!hit && params.quality == QualityMode::Full) {
                col = background(rd);
            }

            // Apply the same post effects as the reference viewer
            const double qx = (static_cast<double>(x) + 0.5) / static_cast<double>(params.width) - 0.5;
            const double qy = (static_cast<double>(y) + 0.5) / static_cast<double>(params.height) - 0.5;
            const double vignette = 1.0 - 0.38 * (qx * qx + qy * qy);
            col = col * vignette;
            col = pow_vec(col, 0.4545);

            // Compute the start index of this pixel inside the flat RGB byte buffer
            const std::size_t idx = (static_cast<std::size_t>(y) * params.width + x) * 3;

            // Convert floating-point 0..1 colours into 8-bit 0..255 bytes
            out.rgb[idx + 0] = static_cast<std::uint8_t>(clamp_double(col.x * 255.0, 0.0, 255.0));
            out.rgb[idx + 1] = static_cast<std::uint8_t>(clamp_double(col.y * 255.0, 0.0, 255.0));
            out.rgb[idx + 2] = static_cast<std::uint8_t>(clamp_double(col.z * 255.0, 0.0, 255.0));

            // Accumulate statistics for the whole frame
            total_steps += steps_taken;
            if (hit) ++hit_pixels;
        }
    }

    // Stop timing the frame now that all pixels are finished
    const auto end = std::chrono::high_resolution_clock::now();
    const double frame_ms = std::chrono::duration<double, std::milli>(end - start).count();

    // Fill the stats struct with the derived frame metrics
    out.stats.frame_ms = frame_ms;
    out.stats.fps = 1000.0 / frame_ms;
    out.stats.pixels_per_second = static_cast<double>(total_pixels) / (frame_ms / 1000.0);
    out.stats.avg_steps = static_cast<double>(total_steps) / static_cast<double>(total_pixels);
    out.stats.hit_ratio = static_cast<double>(hit_pixels) / static_cast<double>(total_pixels);
    out.stats.total_pixels = total_pixels;
    out.stats.total_steps = total_steps;
    out.stats.hit_pixels = hit_pixels;

    return out;
}

/* ============================================================================
   Image output
   ============================================================================ */

// Save a packed RGB buffer as a binary PPM image file
bool save_ppm(const std::string& path, int width, int height, const std::vector<std::uint8_t>& rgb) {
    // Open the file in binary write mode
    FILE* file = std::fopen(path.c_str(), "wb");
    if (!file) return false;

    // Write the PPM header and then the raw RGB bytes
    bool ok = true;
    ok = ok && std::fprintf(file, "P6\n%d %d\n255\n", width, height) > 0;
    ok = ok && std::fwrite(rgb.data(), sizeof(std::uint8_t), rgb.size(), file) == rgb.size();

    // fclose flushes the file and releases the handle
    return std::fclose(file) == 0 && ok;
}
