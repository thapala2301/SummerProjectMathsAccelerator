import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

/* ============================================================================
   Build configuration
   ============================================================================ */

// Export the Vite configuration object
// Vite reads this file when it starts the dev server or creates a production build
export default defineConfig({
    // Enable React support so Vite knows how to transform JSX files
    plugins: [react()],
});
