# CAD — VR Headset

SolidWorks design for a VR headset that holds a small HDMI screen driven by the PYNQ-Z1 and attaches to a Meta Quest 3 head strap.

The motivation: the ray marcher renders in stereo — two eye origins separated by `HALF_IPD` produce a side-by-side left/right image on the HDMI output. The headset provides the optics to view each half-image with the corresponding eye.

---

## Parts

| File | Description |
|------|-------------|
| `front_panel.SLDPRT` | Outer face of the headset, holds the screen and lens mounts |
| `most_front_panel.SLDPRT` | Inner face / secondary panel |
| `screen_panel.SLDPRT` | Cradle for the HDMI screen |
| `eyes_panel.SLDPRT` | Divider panel separating left and right eye regions |
| `foam_support.SLDPRT` | Face cushion mount |
| `body.SLDPRT` | Main structural body |
| `Quest 3 Head band adapter v5.SLDPRT` | Adapter that clips onto the Meta Quest 3 head strap |
| `Quest2Adapter.SLDPRT` | Adapter variant for Meta Quest 2 strap |
| `BodyAdapted.SLDASM` | Full assembly |
| `mechanic(2).SLDASM` | Mechanical sub-assembly |

---

## Assembly

Open `BodyAdapted.SLDASM` in SolidWorks (2021 or later). All parts reference each other locally so no paths need updating if opened from this folder.

The head strap adapter (`Quest 3 Head band adapter v5.SLDPRT`) slots onto the existing Quest 3 halo strap without modification — no tools needed.

<!-- Photo: rendered CAD view of the assembly -->
<!-- ![CAD assembly render](../misc/images/cad_assembly.png) -->

<!-- Photo: 3D-printed prototype assembled -->
<!-- ![Printed headset assembled](../misc/images/headset_assembled.jpg) -->

<!-- Photo: headset worn with PYNQ-Z1 attached -->
<!-- ![Headset worn](../misc/images/headset_worn.jpg) -->

---

## Manufacturing

Parts are designed for FDM 3D printing (PLA or PETG). No support required for most parts if printed in the correct orientation. The foam cushion is attached to `foam_support.SLDPRT` using adhesive-backed foam sheet.
