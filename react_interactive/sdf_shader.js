/* ============================================================================
   Scene distance function source
   ============================================================================ */

/*
Everything inside the template literal below is GLSL, not JavaScript.

The fragment shader pastes this text directly into the final shader source.

The core idea of all the functions in this file is:

"Given a 3D point p, return a number that says how far p seems to be from the
nearest surface."

For the sphere and cube that number is an exact signed distance field.
For the Mandelbox it is a distance estimator, which is a practical approximation
that behaves enough like a distance field for careful ray marching.
*/
export const sdfShaderSource = `
/*
Estimate distance to the Mandelbox surface.

This function is the most conceptually difficult part of the renderer.
The easiest way to think about it is:

1. start with the sample point p
2. repeatedly fold and rescale space around that point
3. watch how far the transformed point ends up from the centre
4. divide by how much the transformations stretched space

That final "distance divided by stretch" idea is what makes the result
distance-like enough for conservative ray marching.
*/
float mandelboxDE(vec3 p) {
    /*
    z is the working point that gets transformed over and over.

    Starting with z = p means:

    "Take the point we are testing and feed it into the Mandelbox iteration."
    */
    vec3 z = p;

    /*
    dr tracks how strongly the iteration stretches nearby distances.

    It is not the exact full derivative matrix.
    It is a scalar magnitude estimate that is good enough for turning the final
    transformed distance back into something meaningful in the original space.
    */
    float dr = 1.0;

    /*
    Use squared radii to avoid unnecessary square roots.

    If r is radius, then:

        r^2 = dot(z, z)

    Comparing squared radii is cheaper than computing length(z) every time.
    */
    float minR2 = uMinRadius * uMinRadius;
    float fixedR2 = uFixedRadius * uFixedRadius;

    for (int i = 0; i < MAX_ITER; i++) {
        if (i >= uIterations) break;

        /*
        === Box fold ===

        This happens component by component.
        For one coordinate x, the formula behaves like a reflection whenever
        x leaves the interval [-uFoldLimit, uFoldLimit].

        Tiny 1D example with uFoldLimit = 1:

        - if x = 0.3
          clamp gives 0.3
          0.3 * 2 - 0.3 = 0.3
          so points already inside stay unchanged

        - if x = 1.3
          clamp gives 1.0
          1.0 * 2 - 1.3 = 0.7
          so the point is mirrored back inward

        - if x = -1.4
          clamp gives -1.0
          -1.0 * 2 - (-1.4) = -0.6
          so it is mirrored back inward on the other side too

        Doing that on X, Y and Z together folds all of space back toward a cube.
        Repeating that fold again and again is one of the main reasons the final
        shape has box-like self-similar detail.
        */
        z = clamp(z, -uFoldLimit, uFoldLimit) * 2.0 - z;

        /*
        r2 is squared distance from the origin.
        It tells the sphere-fold logic how far this transformed point currently
        sits from the centre.
        */
        float r2 = dot(z, z);

        /*
        === Sphere fold ===

        The Mandelbox uses two spherical regions:

        - inner sphere with radius minRadius
        - outer sphere with radius fixedRadius

        Their jobs are:

        - inside the inner sphere:
          use a fixed outward scale to avoid a singularity at the origin
        - between the two spheres:
          perform a true sphere inversion
        - outside the outer sphere:
          leave the point alone

        Why sphere inversion uses fixedR2 / r2 on the whole vector:

        Inversion wants the new radius to be:

            newRadius = R^2 / r

        A vector z has current length r.
        If we scale the whole vector by R^2 / r^2, then the new length becomes:

            r * (R^2 / r^2) = R^2 / r

        which is exactly the inversion rule.
        */
        if (r2 < minR2) {
            /*
            Very close to the origin, true inversion would explode toward
            infinity because r would approach zero.

            So the Mandelbox replaces that unstable region with a constant scale.
            You can think of this as:

            "Pretend every point inside the inner sphere sits on the inner
            sphere boundary before applying the outward push."
            */
            float factor = fixedR2 / minR2;
            z *= factor;
            dr *= factor;
        } else if (r2 < fixedR2) {
            float factor = fixedR2 / r2;
            z *= factor;
            dr *= factor;
        }

        /*
        === Main scale-and-translate step ===

        z = z * uScale + p is the heart of the iterative system.

        - z * uScale
          expands or contracts the transformed point
        - + p
          re-anchors the repeated pattern around the original sample point

        Without the + p, we would just keep transforming around the origin.
        Adding p each round makes the iteration specific to the point being
        tested, which is how a fractal surface emerges in world space.

        Why dr = dr * abs(uScale) + 1.0:

        dr is tracking how strongly the iterative mapping changes when the
        original sample point p changes slightly.

        Very loosely:

        - the z * uScale part scales existing changes by abs(uScale)
        - the + p part contributes one more direct copy of the original-point change

        That is why there is a + 1.0.

        abs(uScale) is used because for distance estimation we care about the
        magnitude of stretching, not whether orientation flipped.
        */
        z = z * uScale + p;
        dr = dr * abs(uScale) + 1.0;
    }

    /*
    === Final distance estimate ===

    By the end of the loop:

    - length(z) says how far the transformed point ended up from the centre
      in the warped Mandelbox iteration space
    - dr says roughly how much that iterative mapping stretched distances

    So:

        length(z) / abs(dr)

    means:

    "Take the final distance seen in warped space, then divide by the amount of
    warping so the answer becomes meaningful back in the original space."

    This is not a perfect exact signed distance field.
    It is a practical distance estimator.
    That is why the ray marcher later uses a conservative 0.85 safety factor
    instead of trusting the value completely.
    */
    return length(z) / abs(dr);
}

/*
Exact signed distance to a sphere of radius 1.25 centred at the origin.

length(p) is the distance from the point to the centre.
Subtracting the sphere radius gives:

- positive outside
- zero on the surface
- negative inside
*/
float sphereDE(vec3 p) {
    return length(p) - 1.25;
}

/*
Exact signed distance to an axis-aligned box centred at the origin.

This is a standard SDF trick:

- abs(p) mirrors the point into the positive octant
- subtracting vec3(1.0) measures distance from the box half-size on each axis
- the final expression combines:
  - outside-corner distance
  - inside-face depth
*/
float cubeDE(vec3 p) {
    vec3 q = abs(p) - vec3(1.0);
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

/*
Choose which scene distance function to evaluate.

This lets the rest of the renderer treat all scenes through one interface:

    "give me a distance-like value for point p"

Even though the Mandelbox is only an estimator and the test shapes are exact
SDFs, they are similar enough in behaviour for the same ray-march loop.
*/
float mapScene(vec3 p) {
    if (uRenderMode == 1) return sphereDE(p);
    if (uRenderMode == 2) return cubeDE(p);
    return mandelboxDE(p);
}
`;
