# macOS Retina fix — "only a corner of the window is drawn"

Patch: [`patches/11-sdl2tk-macos-retina-logical-size.patch`](patches/11-sdl2tk-macos-retina-logical-size.patch)

## The bug

On a **built-in Retina (HiDPI) MacBook display**, undroidwish (and de1app /
Insight running on it) draws its UI into only a **portion of the window** — a
rectangle in one corner, the rest of the window left in the background colour:

- It happens **only on the Retina built-in panel**.
- It does **not** happen on a **non-Retina external display**.
- Dropping the laptop to a **scaled 1× resolution** (e.g. "1147×745") also makes
  it go away — but that resolution is too low for the 1280×800 UI.

![symptom: UI confined to the top-left quadrant of the window]

## Root cause

sdl2tk does **not** render Tk with a GL/Metal-native drawable. Instead it draws
the whole Tk scene into an in-memory `SDL_Surface` (`SdlTkX.sdlsurf`), uploads
that to a streaming `SDL_Texture` (`SdlTkX.sdltex`), and `SDL_RenderCopy`s the
texture to the window each present. The surface and texture are sized in
**window points** (e.g. 1280×800).

On a Retina display the window's **drawable** (the actual GL/Metal framebuffer)
is **window-points × the backing-scale factor** — 2× on Retina, so 2560×1600 for
a 1280×800 window. (This happens even though sdl2tk does **not** set
`SDL_WINDOW_ALLOW_HIGHDPI`; the Cocoa renderer still hands back a 2× drawable on
this SDL/macOS.)

With **no logical size set**, SDL's renderer sets its viewport to the window
**point** size, so `RenderCopy(..., NULL, NULL)` maps the 1280×800 texture into
only the bottom-left `1280×800` of the `2560×1600` drawable — i.e. a
`(1/scale)² = ¼` corner. On a non-Retina display the scale is 1, drawable ==
points, and the copy fills the window — which is why external monitors and the
scaled 1× mode looked fine.

This is the identical mismatch the **iWish / Mac Catalyst** build already cures
with `SDL_RenderSetLogicalSize`, but that call was guarded by
`#if TARGET_OS_MACCATALYST` and therefore compiled **out** of the native macOS
(Cocoa, `TARGET_OS_OSX`) build.

## The fix

Give the renderer a **logical size equal to the point (surface) size** on the
native macOS desktop build, mirroring the Catalyst path. SDL then scales the
present to fill the whole drawable and maps mouse input back into logical space.
When the display scale is 1 (external / non-Retina) this is a **no-op**, so those
displays are unaffected.

Three edits, all in `jni/sdl2tk/sdl/`:

1. **`SdlTkX.c`, display-open (renderer create).** Add a
   `#elif defined(__APPLE__) && defined(TARGET_OS_OSX) && TARGET_OS_OSX` branch
   next to the existing Catalyst one, calling
   `SDL_RenderSetLogicalSize(sdlrend, width, height)`.

2. **`SdlTkX.c`, `HandleRootSize` (window/root resize).** After the surface and
   texture are recreated at the new point size, re-assert the matching logical
   size (same `TARGET_OS_OSX` guard) so a resize stays correct.

3. **`SdlTkGfx.c`, `SdlTkGfxDrawBorgToast`.** The borg-toast overlay positioned
   itself using `SDL_GetRendererOutputSize` (drawable **pixels**). Once a logical
   size is in effect, `RenderCopy` dst rects are interpreted in **logical** space,
   so the raw drawable size would push the toast off-screen by the scale factor.
   Prefer `SDL_RenderGetLogicalSize`, falling back to the output size when no
   logical size is set (unchanged on Android/Linux/Windows and Catalyst).

### Diagnostic

The patch also adds an env-gated, one-shot startup probe. Launch with
`UNDROIDWISH_DPI_LOG=1` and it prints, to stderr:

```
[undroidwish dpi] window(points)=1280x800 drawable(pixels)=2560x1600 surface=1280x800 logical=1280x800
```

On a Retina panel `drawable` is 2× `window`; on a non-Retina display they match.
Harmless (does nothing) when the variable is unset.

## Trade-off

The Tk scene is rendered at 1× and GPU-**upscaled** to fill the Retina drawable,
so text/graphics are slightly soft rather than pixel-crisp — exactly the same
behaviour as the Catalyst build. True 2× rendering would mean driving the entire
Tk drawing stack at the backing resolution, a much larger change. The win is that
at native Retina scaling the 1280×800 UI now **fills the whole window**, so the
low-resolution workaround is no longer needed.
