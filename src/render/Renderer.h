// Draws a Document into any CGContext. The same code path is used by the
// on-screen canvas, by PNG export and by the clipboard, so what you see really
// is what you get.
//
// Coordinate convention: callers must set the CTM so that (0, 0) is the
// top-left corner of the *document* (i.e. of the crop rectangle), one unit is
// one base-image pixel, and y grows downwards.
#pragma once

#include <CoreGraphics/CoreGraphics.h>

#include "model/Document.h"

namespace sk {

// Fills in `a.measuredWidth` / `a.measuredHeight` for text annotations.
void measureText(const Annotation& a);

// Font used for text annotations; also used by the inline editor so the
// on-canvas editing field matches the rendered result.
const char* textFontName();

void drawBaseImage(CGContextRef ctx, const Document& doc, CGImageRef base,
                   CGInterpolationQuality quality = kCGInterpolationHigh);

// `base` is needed by the pixelate tool, which samples the underlying pixels.
void drawAnnotation(CGContextRef ctx, const Annotation& a, const Document& doc, CGImageRef base);

// Base image plus every annotation, in z-order.
void renderDocument(CGContextRef ctx, const Document& doc, CGImageRef base);

// Renders the flattened document into a new CGImage sized to the crop
// rectangle. Caller owns the result (CGImageRelease).
CGImageRef renderToImage(const Document& doc, CGImageRef base);

// Live preview of an in-progress drag that is not in the document yet.
void drawPreview(CGContextRef ctx, const Annotation& a, const Document& doc, CGImageRef base);

}  // namespace sk
