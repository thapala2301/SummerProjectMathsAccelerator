#include "sdf.hpp"

/* ============================================================================
   Individual scene distance estimators
   ============================================================================ */

// Estimate the distance from point p to the Mandelbox fractal surface
// This is a direct CPU translation of the shader maths so benchmark comparisons stay fair
double mandelbox_de(const Vec3& p, const Params& params) {
    // Start with the original input point
    // z will be folded and scaled over and over during the fractal iteration
    Vec3 z = p;

    // dr tracks how the transforms stretch space so we can turn the final point into a distance
    double dr = 1.0;

    // Precompute squared radii because the sphere-fold test works in squared distance
    const double min_r2 = params.min_radius * params.min_radius;
    const double fixed_r2 = params.fixed_radius * params.fixed_radius;

    // Repeat the Mandelbox transform the requested number of times
    for (int i = 0; i < params.iterations; ++i) {
        // Box fold reflects points back into the cube defined by fold_limit
        Vec3 clamped = clamp_vec(z, -params.fold_limit, params.fold_limit);
        z = clamped * 2.0 - z;

        // Measure the squared distance from the origin after the box fold
        const double r2 = dot(z, z);

        // Points in the inner region are pushed outward strongly
        if (r2 < min_r2) {
            const double factor = fixed_r2 / min_r2;
            z = z * factor;
            dr *= factor;
        // Points in the middle band are inverted based on radius
        } else if (r2 < fixed_r2) {
            const double factor = fixed_r2 / r2;
            z = z * factor;
            dr *= factor;
        }

        // Apply the Mandelbox scale and translation for this iteration
        z = z * params.scale + p;
        dr = dr * std::abs(params.scale) + 1.0;
    }

    // Convert the transformed point back into a distance estimate
    return length(z) / std::abs(dr);
}

// Estimate the distance from p to a sphere of radius 1.25 at the origin
double sphere_de(const Vec3& p) {
    return length(p) - 1.25;
}

// Estimate the distance from p to an axis-aligned cube centred at the origin
double cube_de(const Vec3& p) {
    // q stores how far p sits outside the box on each axis
    const Vec3 q = abs_vec(p) - Vec3{1.0, 1.0, 1.0};

    // This standard SDF formula handles both outside and inside points correctly
    return length(max_vec(q, 0.0)) + std::min(std::max(q.x, std::max(q.y, q.z)), 0.0);
}

/* ============================================================================
   Scene dispatcher
   ============================================================================ */

// Choose the correct scene distance function based on the current mode
double map_scene(const Vec3& p, const Params& params) {
    if (params.mode == RenderMode::Sphere) return sphere_de(p);
    if (params.mode == RenderMode::Cube) return cube_de(p);
    return mandelbox_de(p, params);
}
