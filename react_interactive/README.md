# React Interactive Viewer

This folder contains the interactive WebGL viewer for the Mandelbox and the two
simple reference scenes used alongside it.

## Code layout

- `renderer.jsx`
    The top-level viewer component. It owns input handling, overlay UI, mutable
    refs passed to the runtime hook and the visible control panel layout.
- `use_renderer.js`
    The WebGL runtime hook. It owns context creation, shader setup, the animation
    loop, uniform uploads and resource clean-up.
- `camera.js`
    Camera maths plus mutable camera/debug state helpers.
- `webgl.js`
    Low-level WebGL helpers for programme creation, full-screen geometry and uniform
    lookup.
- `params.js`
    Default render parameters and render-mode metadata shared by the UI.
- `control_slider.jsx`
    Reusable slider row used by the controls panel.
- `sdf_shader.js`
    GLSL scene distance functions for Mandelbox, sphere, cube and scene dispatch.
- `shading_shader.js`
    GLSL lighting and background helpers.
- `shaders.js`
    Final assembled vertex and fragment shader source strings.
- `main.jsx`
    React entry point.
- `styles.css`
    Minimal global styles.
- `package.json`
    Project scripts and dependency manifest. This stays comment-free because JSON
    does not support inline comments.

## Run

```bash
npm install
npm run dev
```

The default dev server is configured for `http://127.0.0.1:4174`.
