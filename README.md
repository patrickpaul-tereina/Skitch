# Skitch

A screenshot capture and annotation app for macOS, written in C/C++
(Objective-C++ for the Cocoa glue) and built with CMake.

## Platform support

| | |
| --- | --- |
| **macOS** | The whole app. Capture, editor, icon, installer. |
| **Linux / Windows** | The portable core (`skitch_core`) and its test suite. |

The document model — annotations, hit testing, crop, undo — is plain C++ with
no platform headers, so it compiles anywhere. Everything above it (capture,
rendering, UI) is Cocoa and CoreGraphics, and there is no backend for it on
other platforms yet. Configuring on Linux or Windows therefore builds the core
and its tests and says so, rather than failing:

```
-- Skitch: GUI is macOS-only (Cocoa/CoreGraphics); configured the portable core
   and its tests only.
```

See [Porting](#porting) for what a real port would involve.

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j8
```

On macOS that produces `build/Skitch.app`. Only the Command Line Tools are
required — no Xcode project, no nib files, no third-party dependencies.

```bash
open build/Skitch.app
```

On Linux and Windows the same command produces `libskitch_core` and
`skitch_core_tests`. Any C++17 compiler works; MSVC, GCC and Clang are all
catered for in the warning flags.

To exercise the non-macOS configuration *from* macOS — useful when changing the
build:

```bash
cmake -S . -B build-core -DSKITCH_CORE_ONLY=ON && cmake --build build-core -j8
ctest --test-dir build-core
```

| CMake option | Default | |
| --- | --- | --- |
| `SKITCH_CORE_ONLY` | `OFF` | Build only the portable core, even on macOS |
| `SKITCH_BUILD_TESTS` | `ON` | Build the test suite |

## Installing

The quickest route — builds first if needed, then installs to `/Applications`:

```bash
./scripts/install.sh
```

It quits a running copy, moves any existing install to the Trash (or renames it
aside if the Trash is unavailable — it never deletes outright), copies the
bundle with `ditto` so the code signature survives, and clears the quarantine
flag. Install somewhere else with `DEST="$HOME/Applications" ./scripts/install.sh`.

Equivalent targets from the build system:

```bash
cmake --build build --target install-app   # same script
cmake --install build                      # plain copy, --prefix to redirect
```

To produce a distributable drag-to-install disk image in `build/`:

```bash
./scripts/make-dmg.sh          # or: cmake --build build --target dmg
```

### A note on signing

Builds are ad-hoc signed (`codesign -s -`), not notarised. That is fine on the
machine that built it — no Gatekeeper prompt, no quarantine. Two consequences
worth knowing:

- **Screen Recording is re-requested after each reinstall.** TCC identifies the
  app by bundle ID *and* code signature, and an ad-hoc signature changes
  whenever the binary does. Rebuilding therefore looks like a different app.
- **Copying the `.dmg` to another Mac will trip Gatekeeper.** That user has to
  right-click → Open once, or run
  `xattr -dr com.apple.quarantine /Applications/Skitch.app`.

Both go away with a Developer ID certificate and notarisation.

## Screen Recording permission

macOS gates all screen capture behind TCC. The first launch triggers the system
prompt; if you miss it, enable **Skitch** under *System Settings › Privacy &
Security › Screen Recording*, then quit and reopen the app. Until it is granted,
captures come back empty.

Expect to re-grant this after reinstalling — see the signing note above for why.
Installing once into `/Applications` and leaving it there keeps the grant stable
between uses.

## Using it

Launching the app goes straight into a region capture. Press **Esc** to back out
— you get a menu-bar item (viewfinder icon) and the normal menu bar to work
from. Launch with `--no-capture` to skip the capture on startup, or pass image
paths to open them for annotation.

### Capturing

| Action | Shortcut |
| --- | --- |
| Capture region | `⌘R` (global: `⌃⌥⌘R`) |
| Capture window | `⇧⌘R` (global: `⌃⌥⌘W`) |
| Capture full screen | `⌥⌘R` |
| Capture region after 5s | `⌃⌘R` |
| Open an image file | `⌘O` |
| New from clipboard | `⇧⌘V` |

In the capture overlay: drag to select, hold **Shift** for a square, press
**Space** to switch between region and window mode, **Return** to grab the whole
screen, **Esc** to cancel. Every display is frozen before the overlay appears,
so the overlay itself never lands in the shot.

### Annotating

| Tool | Key | |
| --- | --- | --- |
| Select | `V` | move, resize, reorder, delete existing marks |
| Arrow | `A` | bold tapered arrow |
| Line | `L` | |
| Rectangle | `R` | outline or filled |
| Ellipse | `O` | outline or filled |
| Pen | `P` | smoothed freehand |
| Highlighter | `H` | translucent, multiply-blended |
| Text | `T` | multi-line, edited in place on the canvas |
| Pixelate | `X` | mosaic over anything sensitive |
| Crop | `C` | drag a region; non-destructive and undoable |

Hold **Shift** while dragging to constrain: squares/circles for boxes, 15°
increments for lines and arrows. Colour, stroke width, text size and fill come
from the palette above the canvas. Arrow keys nudge the selection (Shift for
10px steps).

| Action | Shortcut |
| --- | --- |
| Undo / Redo | `⌘Z` / `⇧⌘Z` |
| Revert to Original | `⌥⌘Z` |
| Copy flattened image | `⌘C` |
| Save / Save As | `⌘S` / `⇧⌘S` |
| Bring forward / send backward | `⌘]` / `⌘[` |
| Zoom in / out / 100% / fit | `⌘=` / `⌘-` / `⌘0` / `⌘9` |
| Delete selected mark | `⌫` |

### Rolling back

Every edit is undoable — drawing, moving, resizing, deleting, reordering and
cropping each count as one step, up to 128 deep. `⌘Z` steps back, `⇧⌘Z` forward,
and the `⤺` / `⤻` buttons in the palette do the same.

`⌥⌘Z` (**Edit › Revert to Original**) throws away every mark *and* the crop in
one go, returning the pristine capture. It is itself a single undo step, so
`⌘Z` brings your work back if you reverted by mistake — which is why it does not
ask for confirmation.

While the text tool has an insertion point on the canvas, `⌘Z` undoes your
typing rather than the whole annotation; press `Esc` to finish the text first.

You can also drop an image file onto an editor window to load it.

## How it is put together

```
src/
  model/      Annotation, Document — pure C++, no Cocoa  (-> skitch_core)
  render/     Renderer — draws a Document into any CGContext
  capture/    ScreenCapture, OverlayWindow — CoreGraphics capture + selection UI
  ui/         AppDelegate, EditorWindowController, CanvasView, ToolPalette
  util/       ImageIO (file + pasteboard), Hotkeys (Carbon global hotkeys)
scripts/
  install.sh        install into /Applications
  make-dmg.sh       build a drag-to-install disk image
tools/
  make_icon.mm      generates the app icon
tests/
  core_tests.cpp    portable model tests — run on every platform
  render_smoke.mm   CoreGraphics render + PNG round-trip, macOS only
```

Two decisions shape the rest:

**The document model is platform-free C++.** `sk::Document` holds a vector of
`sk::Annotation` values plus a crop rectangle. Undo is a stack of whole-state
snapshots — annotations are small value types, so copying the vector is cheaper
than maintaining a command hierarchy, and it makes crop undo fall out for free.

**Cropping is non-destructive.** Annotations are always stored in base-image
pixel coordinates and the document carries a crop rectangle into that image.
Cropping never touches the bitmap, so it composes, undoes and re-crops cleanly.
Everything that renders translates by `-cropRect.origin` and clips to the crop
size.

**One renderer, three consumers.** `sk::renderDocument` draws into any
CGContext under a fixed convention — origin at the crop's top-left, one unit per
base-image pixel, y downwards. The canvas, PNG export and the clipboard all go
through it, so the preview is the output.

## The icon

There is no `.icns` or asset catalog in the repo — the icon is drawn in code by
`tools/make_icon.mm` and generated during the build. It shows the product in one
picture: a warm red plate, lit from the upper left; four corner crop marks that
read as a capture frame; and a camera centred inside them, with the lens sunk
into shadow.

The composition is deliberately built from generic parts — corner crop marks and
a camera are both conventions no one owns. The frame is what you point at
something; the camera is what happens next. They are drawn as one object, into a
single transparency layer sharing one gradient and one shadow, and the lens is
punched clean through the camera body with a `destinationOut` fill so the plate
gradient shows in the gap. That gap is what makes the glass read as glass rather
than as a printed dot.

Colour is deliberately unbalanced. The shipping colourway is `signal`: a pale
cool plate with the warmth in the mark rather than the ground, the crop marks a
lighter vermilion than the camera body so the eye reaches the camera first, and
a navy lens so the darkest thing on the icon is still the glass — one focal
point at the centre, rather than the evenly-weighted grey of a toolbar symbol.

Two alternative colourways are kept in the source: `ember` (warm red plate,
ivory glyph, lens sunk into shadow) and `graphite` (quiet navy glyph, one
saturated red lens). Render either without touching the shipping icon:

```bash
SKITCH_ICON_TREATMENT=ember ./build/skitch_iconmaker /tmp/alt.icns /tmp/alt.iconset
```

To ship a different one, change `kShippingPalette` — it is an index into
`kPalettes`.

The artwork is authored on a 1024pt grid and **re-rendered at each native size**
rather than downsampled from one master, so the small variants stay crisp and
can differ where they need to. Four tiers are drawn deliberately rather than
scaled, because a camera inside a frame is two objects competing for the same
few pixels: 128pt and up get everything; 64pt keeps the frame but drops the
shadows and the glint; 32pt drops the frame entirely and grows the camera into
the space it leaves; 16pt goes further and fills the lens solid, since the
one-pixel ring of plate around it is mush at that size. One clear silhouette
beats two faint ones.

The tool also writes the `.icns` container itself (an `icns` magic, a length,
then one `{OSType, length, PNG}` chunk per size) instead of shelling out to
`iconutil`, which keeps the build free of an external dependency. Both the
`.icns` and a browsable `.iconset` directory land in `build/`:

```bash
./build/skitch_iconmaker /tmp/Skitch.icns /tmp/Skitch.iconset
```

To restyle it, edit the `kPalettes` table for colour or `geometryFor` for the
per-tier proportions, and rebuild. `drawPlate` and `drawGlyph` are the only two
drawing functions.

## Tests

```bash
ctest --test-dir build
```

Two suites, split by what they need:

**`skitch_core_tests`** (`tests/core_tests.cpp`) — 107 checks over geometry,
annotation bounds, hit testing for every tool, transforms, the document,
z-order, crop composition and clamping, undo/redo, and revert. No platform
headers, no window server, no permissions; it is what keeps `skitch_core`
honest about being portable, and it is the suite that runs on Linux and
Windows.

**`skitch_render_smoke`** (`tests/render_smoke.mm`) — macOS only, because it
drives CoreGraphics and CoreText. Builds a synthetic screenshot, applies every
tool, renders, and round-trips a PNG, leaving both the cropped and full-frame
results in `build/` for eyeballing.

```bash
./build/skitch_core_tests
./build/skitch_render_smoke /tmp/out.png
```

There is also a UI smoke check that builds a real editor window, renders it
off-screen and exits:

```bash
open build/Skitch.app --args --selftest /tmp/ui.png /path/to/some.png
```

## Porting

`skitch_core` is the part that is already portable. Everything else is a macOS
backend behind it:

| Layer | macOS today | What a port needs |
| --- | --- | --- |
| Capture | `CGDisplayCreateImage`, `CGWindowListCreateImage` | X11/Wayland `xdg-desktop-portal`; Windows `BitBlt` or `Windows.Graphics.Capture` |
| Rendering | CoreGraphics + CoreText in `Renderer.mm` | Skia, Cairo, or Direct2D — plus a text shaper |
| UI | AppKit, written by hand | Qt, GTK, or Win32/WinUI |
| Hotkeys | Carbon `RegisterEventHotKey` | X11 `XGrabKey`; Windows `RegisterHotKey` |
| Image I/O | ImageIO | libpng/libjpeg, or WIC |

The renderer is the one worth planning first. `sk::renderDocument` already has
a single, narrow contract — draw a `Document` into a context whose origin is
the crop's top-left, one unit per base-image pixel, y downwards — so it is the
natural seam for a backend interface rather than a rewrite.
