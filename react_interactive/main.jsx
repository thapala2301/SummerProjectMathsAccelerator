import React from "react";
import { createRoot } from "react-dom/client";

import "./styles.css";
import RaymarchViewer from "./renderer.jsx";

/* ============================================================================
   Application entry point
   ============================================================================ */

// import React from "react" is a default import
// createRoot is a named import, so it appears inside { }
// React components use capitalized names like RaymarchViewer

// Ask React to take control of the single <div id="root"> element in index.html
// This gives React one place in the page where it can create and update the viewer UI
createRoot(document.getElementById("root")).render(
    // StrictMode turns on extra checks while developing
    // It does not change what the final production app does for the user
    <React.StrictMode>
        <RaymarchViewer />
    </React.StrictMode>,
);
