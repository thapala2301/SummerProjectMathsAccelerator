#pragma once

/* ============================================================================
   Scene distance function declarations
   ============================================================================ */

// This header declares the signed-distance functions used by the renderer
// Each scene gets its own function and map_scene chooses which one to call

#include "config.hpp"
#include "vec3.hpp"

// Estimate the distance from a point to the Mandelbox scene
double mandelbox_de(const Vec3& p, const Params& params);

// Estimate the distance from a point to the sphere test scene
double sphere_de(const Vec3& p);

// Estimate the distance from a point to the cube test scene
double cube_de(const Vec3& p);

// Route a distance query to whichever scene Params says is active
double map_scene(const Vec3& p, const Params& params);
