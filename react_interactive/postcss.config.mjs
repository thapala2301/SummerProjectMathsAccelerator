import tailwindcss from "@tailwindcss/postcss";

/* ============================================================================
   CSS processing configuration
   ============================================================================ */

// PostCSS reads this object to decide which CSS tools to run
const config = {
    // Tailwind scans the source files and expands utility classes into real CSS
    plugins: [tailwindcss()],
};

export default config;
