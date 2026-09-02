# Skitch core

This package is **not** the Skitch application. It is `skitch_core`, the
portable part of Skitch: the document model — annotations, geometry, hit
testing, cropping, and undo/redo — as a static library plus its headers.

The Skitch GUI is Cocoa and CoreGraphics, so the app itself ships for macOS
only. This package is what Linux and Windows can offer until there is a
backend for those platforms: everything except the drawing and the windowing.

## What is in here

```
include/skitch/model/Types.h        Vec2, RectD, Color
include/skitch/model/Annotation.h   Annotation, Tool
include/skitch/model/Document.h     Document — the model itself
lib/libskitch_core.a                the library (skitch_core.lib on Windows)
share/doc/Skitch/                   LICENSE, the project README, this file
```

## Using it

The headers include each other as `"model/…"`, so the include root is
`include/skitch`, not `include`:

```cpp
#include "model/Document.h"
#include <cstdio>

int main() {
    sk::Document doc;
    doc.reset(800, 600);          // base image size in pixels

    sk::Annotation a;
    a.tool = sk::Tool::Rect;
    a.p0 = {10, 10};
    a.p1 = {110, 60};
    doc.add(a);

    std::printf("%zu annotation(s), %gx%g\n",
                doc.count(), doc.width(), doc.height());
}
```

```bash
c++ -std=c++17 -Ipath/to/include/skitch main.cpp path/to/lib/libskitch_core.a -o demo
```

With CMake:

```cmake
add_library(skitch_core STATIC IMPORTED)
set_target_properties(skitch_core PROPERTIES
    IMPORTED_LOCATION            "${SKITCH_ROOT}/lib/libskitch_core.a"
    INTERFACE_INCLUDE_DIRECTORIES "${SKITCH_ROOT}/include/skitch")
target_link_libraries(your_target PRIVATE skitch_core)
```

C++17 is required. There are no other dependencies — the library pulls in
nothing beyond the standard library, which is the property that lets it build
anywhere.

## Rendering

Nothing here draws. `Document` holds annotations in base-image pixel
coordinates and a crop rectangle; turning that into pixels is the renderer's
job, and the only renderer that exists is CoreGraphics. Porting means writing
a new one against this same model — see the Porting section of the project
README.

## Licence

GNU General Public License, version 2 only. The full text is in
`share/doc/Skitch/LICENSE`.

Read that before you link against this. The GPL is not a permissive licence:
because this ships as a static library, the terms extend to whatever you link
it into, so a program that uses `skitch_core` has to be GPLv2-compatible and
distributed with its source. Version 2 **only** — there is no "or any later
version" clause, which also rules out combining it with GPLv3-only code.
