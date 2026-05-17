# Capture — App Icon Brief

A 1024×1024 macOS app icon for **Capture**, a tiny menu-bar tool that pops up a Spotlight-style overlay for jotting one quick thought. The icon should sit visually next to its sibling app **Pip** (see reference image) as part of the same personal-tools family, sharing the same canvas treatment but with its own subject and accent color.

## Reference: Pip icon (sibling app)

The Pip icon is a flat-but-dimensional macOS-style icon:

- **Canvas**: a soft, slightly cool off-white squircle (macOS rounded-square shape), with a very subtle vertical gradient from lighter-top to barely-darker-bottom. Soft contact shadow at the bottom edge.
- **Subject**: two centered concentric shapes — a thick **orange ring** (≈ #F8A020, slightly desaturated, with a hint of warm gradient and an inner shadow where it sits on the background) and inside it a **vibrant blue sphere** (≈ #2F7CE8 with a glossy top-left highlight, like a glass ball).
- **Mood**: friendly, slightly playful, modern Big Sur / Sequoia / Tahoe sensibility. No photorealism, no skeuomorphic detail, but real material weight — subtle highlights, soft inner shadows, a believable sense that the shapes are sitting *on* the canvas rather than painted onto it.
- **Composition**: subject centered, occupies ≈ 60–65% of the canvas. Generous breathing room on all sides.

The new Capture icon should match all of the above **canvas, material, and dimensional treatment exactly** — same squircle background, same off-white tone, same glossy "soft solid" style, same scale and centering. Only the **subject** and **accent color** change.

## Capture subject

A stylized **brain, viewed from above** (top-down) — the same view that the SF Symbol `brain.fill` suggests, but rendered with the same dimensional, glossy, "soft solid" material as Pip's blue sphere. Both cerebral hemispheres visible, with the central longitudinal fissure clearly separating them, and a few suggestive gyri/folds curving across each hemisphere. Stylized and simplified — not anatomical or medical, more like a friendly emoji-level abstraction with real shading.

Think: a single glossy organ-shape sitting centered in the squircle, the way Pip's blue sphere sits inside the orange ring. Slight top-left highlight, slight bottom-right shadow, soft contact shadow underneath where it meets the canvas.

## Color

A **single primary accent color**, not two like Pip (Pip's two colors map to its two distinct features; Capture has one purpose). Suggested: **soft violet / electric purple** (≈ #8A5CF5 with a slight gradient toward a deeper violet ≈ #6B3EE0 at the bottom). Purple carries connotations of thought, creativity, and reflection without clashing with Pip's orange.

If purple feels off, alternates that work with the same canvas: **warm coral** (≈ #FF6B7A), **fresh teal** (≈ #2BCFC2), or **amber gold** (≈ #F2B340). Avoid anything in the orange/blue range — those are Pip's.

The brain should be **one color across the whole shape**, with the depth coming entirely from shading: lighter on the top-left lobes, a hint of deeper saturation in the central fissure and the lower edges. No multi-colored sections. No outline stroke.

## Composition

- Brain centered horizontally and vertically.
- Brain occupies ≈ 55–62% of the canvas width (slightly smaller than Pip's orange ring, because the brain shape is more horizontally squat — leave equivalent breathing room).
- Slight tilt is OK if it adds character; perfectly axis-aligned is also fine.
- Soft contact shadow directly below the brain on the canvas, mimicking Pip's grounding.

## What to keep, what to change

| Element | Match Pip | Diverge |
|---|---|---|
| Squircle shape | ✓ identical | |
| Background color & gradient | ✓ identical | |
| Material/material gloss treatment | ✓ identical | |
| Scale and breathing room | ✓ approximately | |
| Center composition | ✓ | |
| Contact shadow | ✓ | |
| Subject | | brain ↔ ring+sphere |
| Number of accent colors | | one (vs two) |
| Accent color choice | | purple (or alt) ↔ orange+blue |

## Negatives — please avoid

- Photorealistic brain texture, blood vessels, anatomical detail
- Multiple colors on the subject (e.g., one hemisphere different from the other)
- An outlined or "sticker-style" border around the brain
- Text or wordmarks anywhere in the icon
- A face, head, or body around the brain — just the brain
- Heavy drop shadows or "glow" effects extending beyond the canvas
- The brain shape extending past the squircle edges or cropped at edges
- Side view, ¾ view, or any view that's not top-down

## Output

- **1024×1024 PNG**, sRGB, transparent background outside the squircle (the squircle itself is opaque off-white).
- Subject and canvas in a single composition — don't render the brain on a transparent background.
- The icon will be converted to `.icns` via `iconutil` for the macOS app bundle, so the squircle alpha needs to be clean (no halo).

## One-line summary if the above is too long

A glossy violet brain, viewed from above, sitting centered on the exact same warm off-white squircle canvas as the Pip icon — same material, same scale, same shading philosophy, just brain-for-rings and violet-for-orange-blue.
