#pragma once

/* ============================================================================
   Minimal vector maths helpers
   ============================================================================ */

// This file defines the small 3D maths helpers used throughout the CPU renderer
// The helpers are kept inline in the header so every source file can use them without needing a
// separate compiled maths library

#include <algorithm>
#include <cmath>

// Vec3 stores one 3D position, direction, normal or colour
struct Vec3 {
    double x;
    double y;
    double z;
};

/* ============================================================================
   Construction and arithmetic
   ============================================================================ */

// Build a Vec3 from three explicit component values
inline Vec3 make_vec3(double x, double y, double z) {
    return Vec3{x, y, z};
}

// Add two vectors component by component
inline Vec3 operator+(const Vec3& a, const Vec3& b) {
    return Vec3{a.x + b.x, a.y + b.y, a.z + b.z};
}

// Subtract one vector from another component by component
inline Vec3 operator-(const Vec3& a, const Vec3& b) {
    return Vec3{a.x - b.x, a.y - b.y, a.z - b.z};
}

// Multiply every component of a vector by the same scalar
inline Vec3 operator*(const Vec3& a, double s) {
    return Vec3{a.x * s, a.y * s, a.z * s};
}

// Support writing scalar * vector as well as vector * scalar
inline Vec3 operator*(double s, const Vec3& a) {
    return a * s;
}

// Divide every component of a vector by the same scalar
inline Vec3 operator/(const Vec3& a, double s) {
    return Vec3{a.x / s, a.y / s, a.z / s};
}

/* ============================================================================
   Scalar helpers
   ============================================================================ */

// Return x when it is finite, otherwise fall back to a safe replacement
inline double finite_or(double x, double fallback = 0.0) {
    return std::isfinite(x) ? x : fallback;
}

// Compute the dot product of two vectors
// This measures how aligned they are and is used all over graphics code
inline double dot(const Vec3& a, const Vec3& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

// Compute the Euclidean length of a vector
inline double length(const Vec3& a) {
    return std::sqrt(dot(a, a));
}

// Clamp a scalar into a safe range
// If x is not finite return the lower bound instead
inline double clamp_double(double x, double lo, double hi) {
    if (!std::isfinite(x)) return lo;
    return std::max(lo, std::min(hi, x));
}

// Linearly blend from a to b using t
// t = 0 gives a and t = 1 gives b
inline double mix_double(double a, double b, double t) {
    return a * (1.0 - t) + b * t;
}

/* ============================================================================
   Vector helpers
   ============================================================================ */

// Convert a vector into a unit-length vector that points the same way
inline Vec3 normalise(const Vec3& a) {
    const double l = length(a);
    if (!std::isfinite(l) || l < 1e-12) return Vec3{0.0, 0.0, 0.0};
    return a / l;
}

// Compute the cross product of two vectors
// The result is perpendicular to both inputs
inline Vec3 cross(const Vec3& a, const Vec3& b) {
    return Vec3{
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    };
}

// Replace each component with its absolute value
inline Vec3 abs_vec(const Vec3& a) {
    return Vec3{std::abs(a.x), std::abs(a.y), std::abs(a.z)};
}

// Replace each component with the larger of itself and v
inline Vec3 max_vec(const Vec3& a, double v) {
    return Vec3{std::max(a.x, v), std::max(a.y, v), std::max(a.z, v)};
}

// Clamp each component of a vector into the same scalar range
inline Vec3 clamp_vec(const Vec3& a, double lo, double hi) {
    return Vec3{
        std::max(lo, std::min(hi, a.x)),
        std::max(lo, std::min(hi, a.y)),
        std::max(lo, std::min(hi, a.z))
    };
}

// Blend two vectors component by component
inline Vec3 mix_vec(const Vec3& a, const Vec3& b, double t) {
    return Vec3{
        mix_double(a.x, b.x, t),
        mix_double(a.y, b.y, t),
        mix_double(a.z, b.z, t)
    };
}

// Raise each vector component to the same power
// Negative or non-finite values are clamped away before pow is applied
inline Vec3 pow_vec(const Vec3& a, double p) {
    return Vec3{
        std::pow(std::max(finite_or(a.x), 0.0), p),
        std::pow(std::max(finite_or(a.y), 0.0), p),
        std::pow(std::max(finite_or(a.z), 0.0), p)
    };
}
