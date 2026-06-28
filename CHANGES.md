# CHANGES — what had to change vs. stock undroidwish

This documents every change required to build **undroidwish** (the
batteries-included SDL2 Tk `wish` from [AndroWish](https://www.androwish.org/),
`undroid/build-undroidwish-macosx.sh`) as a **native Apple-Silicon (arm64)**
binary, instead of the stock x86-64 binary that runs under Rosetta.

Baseline: the AndroWish source tree + its `undroid/build-undroidwish-macosx.sh`
macOS build script. Host used: Apple M4, macOS 26 (Darwin 25), Xcode clang 21,
SDK 26.5. Two package managers present: MacPorts (`/opt/local`, needs sudo) and
Homebrew arm64 (`/opt/homebrew`, no sudo).

Each fix below maps to a patch in [`patches/`](patches/) and is summarized in
[`README.md`](README.md). Categories: **A** toolchain, **B** the core arm64
bug, **C** per-component build fixes, **D** runtime fixes, **E** batteries /
extensions, **F** packaging.

---

## A. Toolchain / build-script (`patches/00-build-undroidwish-macosx.patch`)

### A1. Deployment target 10.10 → 11.0
`CC`/`CXX` hard-coded `-mmacosx-version-min=10.10`. arm64 macOS's minimum is
11.0; 10.10 is invalid for the arm64 slice.

```
-CC="cc  ... -mmacosx-version-min=10.10"
-CXX="c++ ... -mmacosx-version-min=10.10"
+CC="cc  ... -mmacosx-version-min=11.0  <plus the -Wno flags in A2>"
+CXX="c++ ... -mmacosx-version-min=11.0"
```

### A2. clang 21 makes old-code warnings into hard errors
clang 16+ promoted several legacy-C diagnostics to **errors** by default, which
breaks ancient autoconf probe programs and old extension sources. Added to `CC`:

```
-Wno-implicit-int -Wno-implicit-function-declaration -Wno-int-conversion
-Wno-error=incompatible-function-pointer-types -Wno-error=incompatible-pointer-types
```

Without these, e.g. `tcl-augeas.c` failed on `call to undeclared library
function 'free'`, and `trf` failed binding LibreSSL hash functions
(`incompatible function pointer types`).

### A3. Pre-seed autoconf size/type cache (clang SIGPIPE on ancient probes)
clang 21 aborts with a "frontend command failed due to signal" when it receives
**SIGPIPE** during autoconf-2.13's `cc -E | grep` type probes. The probe then
"fails", so `size_t`/`pid_t`/`sizeof` come back wrong and autoconf injects
`#define size_t unsigned`, which poisons every later test (e.g. BLT ended up
with `SIZEOF_VOID_P 0` and an undefined `HashArray`). Fix: export correct cache
values up front so those probes are skipped (harmless to modern TEA configures):

```
ac_cv_type_size_t=yes  ac_cv_type_pid_t=yes
ac_cv_sizeof_int=4  ac_cv_sizeof_long=8  ac_cv_sizeof_long_long=8  ac_cv_sizeof_void_p=8
```

### A4. Use the real system grep/sed (broken Homebrew shim)
A dangling Homebrew shim `/usr/local/bin/egrep -> gnuegrep -> exec gnugrep`
(with `gnugrep` absent) silently returns nothing. Any configure that runs
`egrep` and is early in `PATH` got empty output — notably **mpexpr**, whose
`configure` extracts `MPEXPR_VERSION` via `egrep`, producing an empty version
and a malformed `pkgIndex.tcl` (`package ifneeded Mpexpr  \` with no version →
`expected version number` errors that broke `auto_path` scanning). Fix: prepend
`/usr/bin` to `PATH` in the build script.

---

## B. The core arm64 bug — SDL2 misdetects the Mac as iOS (`patches/01-sdl2-configure-arm64-macos.patch`)

This is the single change that makes the native build actually work.

AndroWish's SDL2 `configure` selects its platform branch on the host triple.
The iOS branch label was:

```
arm*-apple-darwin*|*-ios-*)
```

On Apple Silicon the Mac's host triple is `arm64-apple-darwin25.x`, which
**matches `arm*-apple-darwin*`** → configure took the **iOS** path: it enabled
UIKit + OpenGL ES and **disabled Cocoa**. The build then failed compiling the
GLES renderer (`#include <GLES/gl.h>` — Android/iOS only), and even past that it
would have had no usable video driver (`SDL_VIDEO_DRIVER_DUMMY` only).

On Intel Macs the triple is `x86_64-apple-darwin`, which never matched, so the
stock build silently fell through to the correct `*-*-darwin*` (macOS/Cocoa)
branch — which is why this never bit the x86 build.

Fix: restrict the iOS label to real iOS triples so the arm64 Mac reaches the
macOS branch:

```
-    arm*-apple-darwin*|*-ios-*)
+    *-ios-* | *-iphoneos-*)
```

Result: `SDL_VIDEO_DRIVER_COCOA 1`, GLES off — SDL2 builds for macOS arm64.

The same patch also downgrades `-Werror=declaration-after-statement` →
`-Wno-error=...` (the macOS branch turns it on, and the old Cocoa `.m` files mix
declarations and code).

---

## C. Per-component build fixes

### C1. curl — disable auto-detected zstd (`patches/00`)
The build host has MacPorts `zstd` headers, so curl auto-enabled zstd and
emitted `ZSTD_*` references; the static `libcurl.a` then left them undefined and
`TclCurl` failed to link. The stock x86 build host simply didn't have zstd.
Fix: add `--without-zstd` to curl's configure.

### C2. jpeg-turbo — no aarch64 SIMD (`patches/00`)
The bundled **libjpeg-turbo 1.4.2** (2015) predates aarch64 NEON SIMD; its
`simd/` path is x86 NASM (`-fmacho`) only. On arm64, SIMD couldn't be enabled
and the build produced an empty `libsimd.la` (`ar: no archive members
specified`). Fix: configure `--without-simd` and drop the `make -C simd` /
`-fmacho` perl-fixup steps; build the plain C library.

### C3. tkimg / libpng — undefined NEON symbol (`patches/02-tkimg-libpng-disable-neon.patch`)
`Img` failed to load on arm64:
`symbol not found in flat namespace '_png_init_filter_functions_neon'`.
The bundled libpng sets `PNG_ARM_NEON_OPT 2` on arm64 (so `pngrutil.c`
references the NEON filter init), but `pngtcl`'s Makefile does **not** compile
`arm/arm_init.c` where that symbol is defined → undefined at load. Fix: force
`PNG_ARM_NEON_OPT 0` in `compat/libpng/pngpriv.h` (libpng's own documented
workaround). x86 never used NEON, so it never hit this.

### C4. tkimg / libtiff — undefined codec inits (`patches/03-tkimg-libtiff-disable-codecs.patch`)
After the libpng fix, `Img` then failed with
`symbol not found ... '_TIFFInitPixarLog'`. libtiff's config enables
`PIXARLOG_SUPPORT` and `ZIP_SUPPORT`, so `tif_codec.c` registers
`TIFFInitPixarLog`/`TIFFInitZIP`, but `tifftcl`'s Makefile compiles only 31 of
44 `tif_*.c` and **omits `tif_pixarlog.c`/`tif_zip.c`** → undefined. Fix:
disable those two codecs **in the tracked autoheader templates
`tiffconf.h.in` and `tif_config.h.in`** — replace their `#undef
PIXARLOG_SUPPORT` / `#undef ZIP_SUPPORT` lines with comments so `configure`
cannot define them in the generated `tiffconf.h`/`tif_config.h`. (Earlier this
was done by hand-editing the *generated* headers, but those don't exist in a
fresh checkout, so the patch couldn't apply via `apply-patches.sh`; patching the
`.in` templates is source-level and timing-independent.) TIFF deflate/PixarLog
compression off; PNG/GIF/JPEG/uncompressed/LZW/PackBits/Fax TIFF all still work.
With both C3 and C4, `Img 1.4.11` loads.

---

## D. Runtime fixes

### D1. `sdltk powerinfo` — real battery / 100 on AC (`patches/04-sdl2tk-powerinfo-iokit.patch`)
`sdltk powerinfo` used `SDL_GetPowerInfo`, which misreports on desktop Macs —
notably a Mac with **no internal battery** returns a bogus low percent, which
pushed downstream apps (the de1app) into a low-battery screensaver. Replaced the
macOS/Catalyst path of `PowerinfoObjCmd` (in `sdl2tk/sdl/SdlTkInt.c`) with an
authoritative **IOKit** query (`IOPSCopyPowerSourcesInfo` /
`IOPSGetPowerSourceDescription`), guarded `#if TARGET_OS_OSX ||
TARGET_OS_MACCATALYST`:

- on battery → the **real** battery percentage
- on AC, or no battery at all → **100**

IOKit + CoreFoundation are already linked (SDL2 itself references
`_IOPSCopyPowerSourcesInfo`); if you relink standalone, add `-framework IOKit`.

---

## E. Batteries / extensions

The stock macOS build skips an extension whose external library isn't present.
Installing the libs via **Homebrew (arm64, no sudo)** —
`brew install augeas taglib librdkafka libusb r` — lets four of the five
optional extensions build and load:

| extension   | external lib | result on arm64 |
|-------------|--------------|-----------------|
| tcl-augeas  | augeas       | builds + loads  |
| Rtcl        | R            | builds + loads  |
| kafkatcl    | librdkafka   | builds + loads* |
| tcluvc      | libusb       | builds + loads* |
| tcltaglib   | taglib       | builds; does **not** load (undroidwish's loader rejects the C++ libtag) |

`*` Each extension's `configure` needs to find Homebrew: set
`PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig`,
`CPPFLAGS=-I/opt/homebrew/include`, `LDFLAGS=-L/opt/homebrew/lib`, and pass the
link library explicitly where the package's configure doesn't (e.g. kafkatcl
needs `KAFKALIBS="-L/opt/homebrew/lib -lrdkafka"`).

**rpath:** undroidwish's loader resolves an extension's external dylib via the
binary's `LC_RPATH`. Add `/opt/homebrew/lib` to the final binary
(`install_name_tool -add_rpath /opt/homebrew/lib <wish>`) or these four
extensions can't find their Homebrew libs at load. (This makes the binary depend
on `/opt/homebrew`, unlike the ~60 statically-bundled batteries.)

Also fixed: the **mpexpr `pkgIndex.tcl`** version (see A4) — rebuilding mpexpr
with a working `egrep` yields `package ifneeded Mpexpr 1.2 ...`.

---

## F. Packaging & build hygiene

### F1. arm64 binaries must be code-signed
x86 wish ran unsigned; an arm64 Mach-O must carry at least an ad-hoc signature
or the OS kills it. After assembling the single-file binary
(`wish` + appended `assets.zip`), `codesign --force --sign - <binary>`.
`codesign -v` reports "failed strict validation" because of the appended ZIP
after the Mach-O — that's expected; the executable pages are validly signed and
it runs. For distribution, Developer-ID sign + notarize.

### F2. Clean the out-of-tree build dir before building
`build-...-macosx.sh init` rsyncs sources that may carry stale objects from a
previous (e.g. Mac-Catalyst) attempt. Before `build`, delete stale `*.o`,
`*.a`, libtool `*.lo`, and `config.cache` files in the working dir — otherwise
make skips recompiling (timestamps) and links wrong-arch / wrong-platform
objects, or a stale Catalyst `config.cache` aborts a configure with "changes in
the environment can compromise the build".

---

## G. Desktop `borg` command (`patches/05`, `patches/06`)

Stock undroidwish is "AndroWish sans the borg": the Android `borg`
(`jni/src/tkBorg.c`, a ~6900-line JNI bridge) is not compiled in, so AndroWish
code that calls `borg …` fails with *invalid command name "borg"*.

**G1** New file **`jni/src/tkBorgOSX.c`** — a self-contained, `__APPLE__`-guarded
reimplementation of `borg` for the macOS desktop, built as a loadable Tcl stubs
package (`package require Borg`). Its subcommand surface matches the documented
Android command exactly; every documented subcommand exists and never raises a
Tcl error on a well-formed call. Native where macOS maps (`say`, `open`,
`osascript`, IOKit USB, CoreGraphics display metrics, sysctl device/OS info,
`getifaddrs` network state, `DisplayServices` brightness via `dlopen`, a typed
file-backed `sharedpreferences` store, a Tk toast/spinner); safe Android-shaped
no-ops where there is no analog (NFC, telephony, content providers, intents,
sensors, camera, location). Uses only already-linked frameworks (CoreFoundation,
CoreGraphics, IOKit) plus standard CLI tools via `posix_spawn` — no new hard
dependency. Per-command status: [`BORG-OSX.md`](BORG-OSX.md).

**G2** Build-script wiring: a `build borg` step compiles `tkBorgOSX.c` into
`${PFX_HERE}/lib/Borg1.0/` with a `pkgIndex.tcl`, and the assets-assembly step
copies `Borg*` into `assets.zip`.

**G3** Toast geometry (`patches/05`, `patches/07`): the `borg toast` overlay is
**sized in Tcl** — `tkBorgOSX.c` `::borg::ui::_toast_sdl` uses font
`int(sh/30*0.7)` (~30% smaller) and the box scales with it — but
**positioned in C**. `SdlTkGfxDrawBorgToast()` (`SdlTkGfx.c`) composites the
captured pixels at `dst.y = oh - dst.h - oh*0.02`, i.e. sitting against the
bottom edge with a ~2% margin. GOTCHA: the Tcl `wm geometry` of the toast
toplevel only places the *offscreen capture* window whose pixels are grabbed;
it does NOT control the on-screen position — that is solely the C compositor.

Verified on Apple Silicon (macOS 26 / Darwin 25): all documented subcommands
load and run; native commands return correct data; malformed calls still report
the usual `wrong # args` / `bad option` diagnostics.

---

## Summary of files touched

| file | change |
|------|--------|
| `undroid/build-undroidwish-macosx.sh` | A1–A4, C1, C2, G2 |
| `jni/SDL2/configure` | B (iOS→macOS branch), declaration-after-statement |
| `jni/tkimg/compat/libpng/pngpriv.h` | C3 (NEON off) |
| `jni/tkimg/compat/libtiff/libtiff/{tiffconf.h,tif_config.h}.in` | C4 (codecs off, via templates) |
| `jni/sdl2tk/sdl/SdlTkInt.c` | D1 (powerinfo via IOKit) |
| `jni/src/tkBorgOSX.c` | G1 (new — desktop `borg` for macOS) |

The result runs natively on Apple Silicon (verified: `tclsh8.6`/`wish` report
`arm64`; Tcl regression suite passes — 46090 tests, 1 environment-only failure).

## H — sdl2tk dirty-rect present (patch 08)

`SdlTkGfxUpdateRegion` (non-Android branch) used to `SDL_UpdateTexture(tex, NULL, ...)`
the **whole** surface on every present (added in patch 07 to keep the root background
correct after expose). During steady-state animation that re-uploaded the entire
surface each frame even though the per-rect loop below already uploads the changed
pixels. Patch 08 gates that full upload on a new `SDLTKX_FULLSYNC` flag, set in
`SdlTkScreenRefresh` only when the root was exposed (`screen_dirty_region`) or a full
redraw was requested (`SDLTKX_DRAWALL`: resize, pan/zoom, show/restore, init). So the
background guard still fires on every background-changing event, but ordinary content
frames skip the blanket upload. Behavior-preserving; verified on macOS (expose/resize)
and on a real iOS device.
