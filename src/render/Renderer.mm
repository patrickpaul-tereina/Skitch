// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#include "render/Renderer.h"

#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

#include <vector>

namespace sk {

namespace {

CGColorSpaceRef sharedColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    return cs;
}

void setStroke(CGContextRef ctx, const Color& c) {
    CGContextSetRGBStrokeColor(ctx, c.r, c.g, c.b, c.a);
}

void setFill(CGContextRef ctx, const Color& c) {
    CGContextSetRGBFillColor(ctx, c.r, c.g, c.b, c.a);
}

CGRect toCG(const RectD& r) { return CGRectMake(r.x, r.y, r.w, r.h); }

// ---------------------------------------------------------------- text ----

CTFontRef createFont(double size) {
    CFStringRef name = CFSTR("HelveticaNeue-Bold");
    CTFontRef f = CTFontCreateWithName(name, size, nullptr);
    if (!f) f = CTFontCreateWithName(CFSTR("Helvetica-Bold"), size, nullptr);
    return f;
}

std::vector<std::string> splitLines(const std::string& s) {
    std::vector<std::string> out;
    std::string cur;
    for (char ch : s) {
        if (ch == '\n') {
            out.push_back(cur);
            cur.clear();
        } else {
            cur.push_back(ch);
        }
    }
    out.push_back(cur);
    return out;
}

CTLineRef createLine(const std::string& utf8, CTFontRef font, const Color& color) {
    CFStringRef str = CFStringCreateWithBytes(kCFAllocatorDefault,
                                              reinterpret_cast<const UInt8*>(utf8.data()),
                                              static_cast<CFIndex>(utf8.size()),
                                              kCFStringEncodingUTF8, false);
    if (!str) return nullptr;

    const CGFloat comps[4] = {static_cast<CGFloat>(color.r), static_cast<CGFloat>(color.g),
                              static_cast<CGFloat>(color.b), static_cast<CGFloat>(color.a)};
    CGColorRef cg = CGColorCreate(sharedColorSpace(), comps);

    CFStringRef keys[] = {kCTFontAttributeName, kCTForegroundColorAttributeName};
    CFTypeRef values[] = {font, cg};
    CFDictionaryRef attrs = CFDictionaryCreate(
        kCFAllocatorDefault, reinterpret_cast<const void**>(keys),
        reinterpret_cast<const void**>(values), 2, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);

    CFAttributedStringRef attributed =
        CFAttributedStringCreate(kCFAllocatorDefault, str, attrs);
    CTLineRef line = CTLineCreateWithAttributedString(attributed);

    CFRelease(attributed);
    CFRelease(attrs);
    CGColorRelease(cg);
    CFRelease(str);
    return line;
}

double lineHeightFor(double fontSize) { return fontSize * 1.28; }

// ------------------------------------------------------------ pixelate ----

// Returns a heavily downsampled copy of `sub`, or null on failure.
CGImageRef createMosaic(CGImageRef sub, double blockSize) {
    const size_t sw = CGImageGetWidth(sub);
    const size_t sh = CGImageGetHeight(sub);
    if (sw == 0 || sh == 0) return nullptr;

    const double block = std::max(2.0, blockSize);
    size_t tw = static_cast<size_t>(std::max(1.0, std::floor(sw / block)));
    size_t th = static_cast<size_t>(std::max(1.0, std::floor(sh / block)));

    CGContextRef small = CGBitmapContextCreate(nullptr, tw, th, 8, 0, sharedColorSpace(),
                                               kCGImageAlphaPremultipliedFirst |
                                                   kCGBitmapByteOrder32Host);
    if (!small) return nullptr;
    CGContextSetInterpolationQuality(small, kCGInterpolationMedium);
    CGContextDrawImage(small, CGRectMake(0, 0, tw, th), sub);
    CGImageRef out = CGBitmapContextCreateImage(small);
    CGContextRelease(small);
    return out;
}

void drawPixelate(CGContextRef ctx, const Annotation& a, CGImageRef base) {
    if (!base) return;
    const RectD r = RectD::fromCorners(a.p0, a.p1);
    if (r.w < 2.0 || r.h < 2.0) return;

    const RectD clipped =
        r.intersect(RectD(0, 0, CGImageGetWidth(base), CGImageGetHeight(base)));
    if (clipped.isEmpty()) return;

    // CGImage sub-rects use the same top-left origin as our document space.
    CGImageRef sub = CGImageCreateWithImageInRect(base, toCG(clipped));
    if (!sub) return;

    CGImageRef mosaic = createMosaic(sub, a.blockSize);
    CGImageRelease(sub);
    if (!mosaic) return;

    CGContextSaveGState(ctx);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGContextTranslateCTM(ctx, clipped.x, clipped.y + clipped.h);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextDrawImage(ctx, CGRectMake(0, 0, clipped.w, clipped.h), mosaic);
    CGContextRestoreGState(ctx);

    CGImageRelease(mosaic);
}

// ------------------------------------------------------------ squircle ----

// The superellipse |x/a|^4 + |y/b|^4 = 1 inscribed in `r`. Its parametric form
// is x = a·sgn(cos t)·|cos t|^(1/2), and likewise for y. A fixed 256-gon is
// smooth at any size: the points crowd into the corners where the curve turns,
// and the long segments land on the sides, which are close to straight.
void addSquircle(CGMutablePathRef path, const RectD& r) {
    const Vec2 c = r.center();
    const double a = r.w * 0.5, b = r.h * 0.5;
    const int kSteps = 256;
    for (int i = 0; i < kSteps; ++i) {
        const double t = 2.0 * M_PI * i / kSteps;
        const double ct = std::cos(t), st = std::sin(t);
        const double x = c.x + a * std::copysign(std::sqrt(std::fabs(ct)), ct);
        const double y = c.y + b * std::copysign(std::sqrt(std::fabs(st)), st);
        if (i == 0) CGPathMoveToPoint(path, nullptr, x, y);
        else CGPathAddLineToPoint(path, nullptr, x, y);
    }
    CGPathCloseSubpath(path);
}

// --------------------------------------------------------------- arrow ----

// A tapered arrow: thin at the tail, flaring into a solid head.
void buildArrowPath(CGMutablePathRef path, const Annotation& a) {
    const Vec2 d = a.p1 - a.p0;
    const double len = d.length();
    if (len < 1e-6) return;

    const Vec2 u = d.normalized();
    const Vec2 n = u.perp();

    const double w = std::max(1.0, a.lineWidth);
    const double headLen = std::min(len * 0.45, w * 4.2);
    const double headHalf = std::max(w * 2.0, headLen * 0.52);
    const double tailHalf = std::max(0.5, w * 0.30);
    const double shaftHalf = std::max(tailHalf, w * 0.55);

    const Vec2 base = a.p1 - u * headLen;

    auto pt = [&](const Vec2& origin, double along, double side) {
        const Vec2 v = origin + u * along + n * side;
        return CGPointMake(v.x, v.y);
    };

    CGPathMoveToPoint(path, nullptr, pt(a.p0, 0, tailHalf).x, pt(a.p0, 0, tailHalf).y);
    CGPathAddLineToPoint(path, nullptr, pt(base, 0, shaftHalf).x, pt(base, 0, shaftHalf).y);
    CGPathAddLineToPoint(path, nullptr, pt(base, 0, headHalf).x, pt(base, 0, headHalf).y);
    CGPathAddLineToPoint(path, nullptr, a.p1.x, a.p1.y);
    CGPathAddLineToPoint(path, nullptr, pt(base, 0, -headHalf).x, pt(base, 0, -headHalf).y);
    CGPathAddLineToPoint(path, nullptr, pt(base, 0, -shaftHalf).x, pt(base, 0, -shaftHalf).y);
    CGPathAddLineToPoint(path, nullptr, pt(a.p0, 0, -tailHalf).x, pt(a.p0, 0, -tailHalf).y);
    CGPathCloseSubpath(path);
}

// ------------------------------------------------------------ freehand ----

void addSmoothPolyline(CGMutablePathRef path, const std::vector<Vec2>& pts) {
    if (pts.empty()) return;
    CGPathMoveToPoint(path, nullptr, pts[0].x, pts[0].y);
    if (pts.size() < 3) {
        for (size_t i = 1; i < pts.size(); ++i) {
            CGPathAddLineToPoint(path, nullptr, pts[i].x, pts[i].y);
        }
        return;
    }
    // Quadratic segments through the midpoints give a smooth stroke without
    // needing a full spline fit.
    for (size_t i = 1; i + 1 < pts.size(); ++i) {
        const double mx = (pts[i].x + pts[i + 1].x) * 0.5;
        const double my = (pts[i].y + pts[i + 1].y) * 0.5;
        CGPathAddQuadCurveToPoint(path, nullptr, pts[i].x, pts[i].y, mx, my);
    }
    CGPathAddLineToPoint(path, nullptr, pts.back().x, pts.back().y);
}

}  // namespace

// ============================================================== public ====

const char* textFontName() { return "HelveticaNeue-Bold"; }

void measureText(const Annotation& a) {
    if (a.tool != Tool::Text) return;

    CTFontRef font = createFont(a.fontSize);
    if (!font) return;

    const std::vector<std::string> lines = splitLines(a.text);
    double maxWidth = 0.0;
    for (const std::string& l : lines) {
        const std::string probe = l.empty() ? std::string(" ") : l;
        CTLineRef line = createLine(probe, font, a.stroke);
        if (line) {
            maxWidth = std::max(maxWidth, CTLineGetTypographicBounds(line, nullptr, nullptr, nullptr));
            CFRelease(line);
        }
    }
    CFRelease(font);

    a.measuredWidth = std::max(maxWidth, a.fontSize * 0.6);
    a.measuredHeight = lineHeightFor(a.fontSize) * static_cast<double>(lines.size());
}

void drawBaseImage(CGContextRef ctx, const Document& doc, CGImageRef base,
                   CGInterpolationQuality quality) {
    if (!base) return;
    const double w = doc.baseWidth();
    const double h = doc.baseHeight();

    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, -doc.cropRect().x, -doc.cropRect().y);
    CGContextTranslateCTM(ctx, 0.0, h);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextSetInterpolationQuality(ctx, quality);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), base);
    CGContextRestoreGState(ctx);
}

void drawAnnotation(CGContextRef ctx, const Annotation& a, const Document& doc,
                    CGImageRef base) {
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, -doc.cropRect().x, -doc.cropRect().y);

    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextSetLineWidth(ctx, std::max(1.0, a.lineWidth));
    setStroke(ctx, a.stroke);
    setFill(ctx, a.fill);

    switch (a.tool) {
        case Tool::Arrow: {
            CGMutablePathRef p = CGPathCreateMutable();
            buildArrowPath(p, a);
            CGContextAddPath(ctx, p);
            setFill(ctx, a.stroke);
            CGContextFillPath(ctx);
            CGPathRelease(p);
            break;
        }

        case Tool::Line: {
            CGContextMoveToPoint(ctx, a.p0.x, a.p0.y);
            CGContextAddLineToPoint(ctx, a.p1.x, a.p1.y);
            CGContextStrokePath(ctx);
            break;
        }

        case Tool::Rect: {
            const CGRect r = toCG(RectD::fromCorners(a.p0, a.p1));
            if (a.filled) {
                setFill(ctx, a.fill);
                CGContextFillRect(ctx, r);
            }
            CGContextStrokeRect(ctx, r);
            break;
        }

        case Tool::Ellipse: {
            const CGRect r = toCG(RectD::fromCorners(a.p0, a.p1));
            if (a.filled) {
                setFill(ctx, a.fill);
                CGContextFillEllipseInRect(ctx, r);
            }
            CGContextStrokeEllipseInRect(ctx, r);
            break;
        }

        case Tool::Squircle: {
            CGMutablePathRef p = CGPathCreateMutable();
            addSquircle(p, RectD::fromCorners(a.p0, a.p1));
            if (a.filled) {
                setFill(ctx, a.fill);
                CGContextAddPath(ctx, p);
                CGContextFillPath(ctx);
            }
            CGContextAddPath(ctx, p);
            CGContextStrokePath(ctx);
            CGPathRelease(p);
            break;
        }

        case Tool::Pen: {
            if (a.points.size() == 1) {
                setFill(ctx, a.stroke);
                const double r = std::max(0.5, a.lineWidth * 0.5);
                CGContextFillEllipseInRect(
                    ctx, CGRectMake(a.points[0].x - r, a.points[0].y - r, r * 2, r * 2));
                break;
            }
            CGMutablePathRef p = CGPathCreateMutable();
            addSmoothPolyline(p, a.points);
            CGContextAddPath(ctx, p);
            CGContextStrokePath(ctx);
            CGPathRelease(p);
            break;
        }

        case Tool::Highlighter: {
            CGContextSetBlendMode(ctx, kCGBlendModeMultiply);
            CGContextSetLineCap(ctx, kCGLineCapSquare);
            CGContextSetLineWidth(ctx, std::max(6.0, a.lineWidth * 3.0));
            setStroke(ctx, a.stroke.withAlpha(std::min(a.stroke.a, 0.42)));
            if (a.points.size() == 1) {
                const double r = std::max(3.0, a.lineWidth * 1.5);
                setFill(ctx, a.stroke.withAlpha(0.42));
                CGContextFillRect(
                    ctx, CGRectMake(a.points[0].x - r, a.points[0].y - r, r * 2, r * 2));
            } else {
                CGMutablePathRef p = CGPathCreateMutable();
                addSmoothPolyline(p, a.points);
                CGContextAddPath(ctx, p);
                CGContextStrokePath(ctx);
                CGPathRelease(p);
            }
            break;
        }

        case Tool::Pixelate:
            drawPixelate(ctx, a, base);
            break;

        case Tool::Redact: {
            // Out to whole base-image pixels, so no antialiased edge leaves a
            // partly covered pixel behind. Opaque and normal-blended whatever
            // the chosen colour, so nothing underneath shows through.
            const RectD r = RectD::fromCorners(a.p0, a.p1);
            const double x0 = std::floor(r.minX()), y0 = std::floor(r.minY());
            const double x1 = std::ceil(r.maxX()), y1 = std::ceil(r.maxY());
            CGContextSetBlendMode(ctx, kCGBlendModeNormal);
            CGContextSetAlpha(ctx, 1.0);
            setFill(ctx, a.stroke.withAlpha(1.0));
            CGContextFillRect(ctx, CGRectMake(x0, y0, x1 - x0, y1 - y0));
            break;
        }

        case Tool::Text: {
            measureText(a);
            CTFontRef font = createFont(a.fontSize);
            if (font) {
                const std::vector<std::string> lines = splitLines(a.text);
                const double lh = lineHeightFor(a.fontSize);
                const double ascent = CTFontGetAscent(font);
                for (size_t i = 0; i < lines.size(); ++i) {
                    if (lines[i].empty()) continue;
                    CTLineRef line = createLine(lines[i], font, a.stroke);
                    if (!line) continue;
                    CGContextSaveGState(ctx);
                    CGContextTranslateCTM(ctx, a.p0.x,
                                          a.p0.y + lh * static_cast<double>(i) + ascent);
                    CGContextScaleCTM(ctx, 1.0, -1.0);
                    CGContextSetTextPosition(ctx, 0.0, 0.0);
                    CTLineDraw(line, ctx);
                    CGContextRestoreGState(ctx);
                    CFRelease(line);
                }
                CFRelease(font);
            }
            break;
        }

        default:
            break;
    }

    CGContextRestoreGState(ctx);
}

void drawPreview(CGContextRef ctx, const Annotation& a, const Document& doc,
                 CGImageRef base) {
    drawAnnotation(ctx, a, doc, base);
}

void renderDocument(CGContextRef ctx, const Document& doc, CGImageRef base) {
    drawBaseImage(ctx, doc, base);
    for (const Annotation& a : doc.items()) {
        drawAnnotation(ctx, a, doc, base);
    }
}

CGImageRef renderToImage(const Document& doc, CGImageRef base) {
    const size_t w = static_cast<size_t>(std::max(1.0, std::round(doc.width())));
    const size_t h = static_cast<size_t>(std::max(1.0, std::round(doc.height())));

    CGContextRef ctx = CGBitmapContextCreate(
        nullptr, w, h, 8, 0, sharedColorSpace(),
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    if (!ctx) return nullptr;

    // Flip into the document convention: origin top-left, y downwards.
    CGContextTranslateCTM(ctx, 0.0, static_cast<CGFloat>(h));
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextSetShouldAntialias(ctx, true);

    renderDocument(ctx, doc, base);

    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return out;
}

}  // namespace sk
