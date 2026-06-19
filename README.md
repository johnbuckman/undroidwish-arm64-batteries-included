# undroidwish-arm64-batteries-included

Build [AndroWish](https://www.androwish.org/)'s **undroidwish** — the
batteries-included, single-file SDL2 `wish` — as a **native Apple-Silicon
(arm64)** macOS binary, instead of the stock x86-64 build that runs under
Rosetta.

This repo is a **recipe**: a small set of patches plus documentation. It does
**not** redistribute the AndroWish source (which has its own licenses); you
clone AndroWish, apply these patches, and run its build script.

The result is a self-contained `wish` with ~60 statically-linked Tcl/Tk
extensions (Img, tls, tdom, BLT, tkpath, itk, tktreectrl, snack, mpexpr, …),
running natively on arm64. Verified: native `tclsh8.6`/`wish` report `arm64`,
and the Tcl regression suite passes (46090 tests, 1 environment-only failure).

See [`CHANGES.md`](CHANGES.md) for a detailed, rationale-by-rationale account of
everything that had to change from stock undroidwish.

## Why it's needed

Stock undroidwish builds x86-64 on macOS. Building it for arm64 surfaces a chain
of issues, the central one being that AndroWish's SDL2 `configure` treats the
Apple-Silicon Mac (host triple `arm64-apple-darwin…`) as **iOS** — enabling
UIKit/OpenGL ES and disabling Cocoa — because its iOS branch label
`arm*-apple-darwin*` swallows arm64 Macs. The rest are modern-clang strictness,
ancient-autoconf probes, x86-only SIMD paths, and a couple of bundled-library
codec gaps. All are documented and patched here.

## Prerequisites

- Apple Silicon Mac, macOS 11+ (developed on macOS 26 / M4).
- **Xcode command-line tools** (clang, `swiftc`).
- **MacPorts** (`/opt/local`) for `autoconf`, `automake`, `pkg-config`, `cmake`.
- **VLC.app** (arm64) if you want the `tkvlc`/VLC bits (the build's `ADD_RPATH`
  points at it).
- An **AndroWish source checkout** (the build's baseline).
- *(Optional, for the extra extensions in `E` below)* **Homebrew (arm64)** and:
  ```
  brew install augeas taglib librdkafka libusb r
  ```

## Build

```sh
# 1. Get AndroWish (its repo / fossil mirror) — call its root $AW
#    https://www.androwish.org/  (fossil) or a git mirror.

# 2. Apply the patches from this repo to $AW:
cd "$AW"
/path/to/undroidwish-arm64-batteries-included/apply-patches.sh "$AW"

# 3. Build out-of-tree (the script refuses to run inside the AndroWish tree):
mkdir -p ~/build-uw-arm64 && cd ~/build-uw-arm64
bash "$AW/undroid/build-undroidwish-macosx.sh" init     # copy sources

# 4. Scrub stale artifacts the init may have carried in (see CHANGES F2):
find . -name '*.o' -delete
find . -name '*.a' ! -path '*win32*' ! -path '*win64*' -delete
# delete every libtool .lo whose backing object is gone, and any config.cache:
find . -name 'config.cache' -delete

# 5. Build:
bash "$AW/undroid/build-undroidwish-macosx.sh" build
```

You'll get `undroidwish` (the single-file binary), `undroidwish.app`, and
`undroidwish.dmg` in the build directory.

### Install as `undroidwish-arm64`

To keep it side-by-side with an x86 `undroidwish`:

```sh
APP=/Applications/undroidwish-arm64.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# the single-file binary = the wish + appended assets.zip the build produced:
cp -p undroidwish "$APP/Contents/MacOS/undroidwish-arm64"
# arm64 requires a signature (ad-hoc is fine for local use):
codesign --force --sign - "$APP/Contents/MacOS/undroidwish-arm64"
ln -sf "$APP/Contents/MacOS/undroidwish-arm64" /usr/local/bin/undroidwish-arm64
```

### Optional extensions needing Homebrew libs

After `brew install …` (above), the four loadable extras (augeas, Rtcl,
kafkatcl, tcluvc) need their per-component configure pointed at Homebrew and the
final binary needs `/opt/homebrew/lib` on its rpath — see
[`CHANGES.md` §E](CHANGES.md). `tcltaglib` compiles but does not load.

## The patches

| patch | what |
|-------|------|
| `patches/00-build-undroidwish-macosx.patch` | toolchain: arm64 min version, clang-21 flag relaxations, autoconf cache seed, real-grep PATH, curl `--without-zstd`, SDL2 `--disable-video-opengles`, jpeg-turbo `--without-simd` |
| `patches/01-sdl2-configure-arm64-macos.patch` | **the core fix**: arm64 Mac hits the macOS/Cocoa branch, not iOS; relax `declaration-after-statement` |
| `patches/02-tkimg-libpng-disable-neon.patch` | force `PNG_ARM_NEON_OPT 0` (undefined NEON symbol) |
| `patches/03-tkimg-libtiff-disable-codecs.patch` | disable uncompiled PixarLog/ZIP TIFF codecs (in the tracked `*.h.in` templates) |
| `patches/04-sdl2tk-powerinfo-iokit.patch` | `sdltk powerinfo` via IOKit (real battery, 100 on AC/no-battery) |
| `patches/05-borg-osx-tkBorgOSX.c.patch` | **new file** `jni/src/tkBorgOSX.c` — a desktop `borg` command for macOS (see [`BORG-OSX.md`](BORG-OSX.md)) |
| `patches/06-borg-osx-build-undroidwish-macosx.patch` | build + bundle the `Borg` package into `assets.zip` |

Apply with `apply-patches.sh`, or individually with `git apply` / `patch -p1`
from the AndroWish root.

## The desktop `borg` command (macOS)

Stock undroidwish is *"AndroWish sans the borg"* — the Android `borg` command
(`jni/src/tkBorg.c`, a JNI bridge) is not compiled in, so code written for
AndroWish that calls `borg …` fails with *invalid command name "borg"*.

Patches 05/06 add **`jni/src/tkBorgOSX.c`**, a self-contained macOS
implementation built as a loadable Tcl stubs package (`package require Borg`),
bundled into `assets.zip`. Its subcommand surface matches the documented
Android command exactly; every documented subcommand exists and **never errors
on a well-formed call**. Where a macOS facility maps it does the real thing
(`say`, `open`, IOKit, CoreGraphics, a typed prefs store); where there is no
analog (NFC, telephony, Android content providers/intents) it is a safe no-op
returning the Android-shaped empty value. Full per-command status is in
[`BORG-OSX.md`](BORG-OSX.md).

## License

The patches, scripts, and documentation in this repository are licensed under
the **GNU General Public License v3.0** (see [`LICENSE`](LICENSE)). They are
modifications to / instructions for the AndroWish project; **AndroWish and the
third-party libraries it bundles retain their own original licenses.**
