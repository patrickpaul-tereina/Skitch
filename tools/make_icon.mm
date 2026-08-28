// Draws the app icon and writes a full .iconset directory.
//
//   ./skitch_iconmaker <output.icns> [output.iconset dir]
//
// The artwork is vector, re-rendered at each native size rather than
// downsampled from 1024, so the small sizes stay crisp.
//
// The drawing is a capture frame — four corner crop marks — with a camera
// centred inside it. Set SKITCH_ICON_TREATMENT to one of the palette names in
// kPalettes to render an alternative colourway instead of the shipping one.

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

namespace {

// Everything below is authored on a 1024x1024 grid and scaled per output size.
constexpr double kGrid = 1024.0;

// Apple's macOS icon template: an 824pt rounded square centred in 1024pt.
constexpr double kPlateInset = 100.0;
constexpr double kPlateRadius = 185.0;

/// How much artwork a given output size can carry. The crop marks and the
/// camera are two objects competing for the same few pixels, so the small
/// tiers give up the frame entirely and let the camera fill the plate. Each
/// tier is drawn deliberately rather than scaled down.
enum class Detail {
    Nano,   // 16px: camera only, filled lens, no gap ring.
    Micro,  // 32px: camera only, still no frame, lens keeps its ring.
    Small,  // 64px: frame returns, no shadows, no catchlight.
    Full,   // 128px and up: the whole drawing.
};

Detail detailFor(size_t pixels) {
    if (pixels <= 16) return Detail::Nano;
    if (pixels <= 32) return Detail::Micro;
    if (pixels <= 64) return Detail::Small;
    return Detail::Full;
}

struct RGBA {
    double r, g, b, a;
};

void setFill(CGContextRef ctx, RGBA c) { CGContextSetRGBFillColor(ctx, c.r, c.g, c.b, c.a); }

void setShadow(CGContextRef ctx, CGSize offset, double blur, RGBA c) {
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    const CGFloat comps[4] = {(CGFloat)c.r, (CGFloat)c.g, (CGFloat)c.b, (CGFloat)c.a};
    CGColorRef color = CGColorCreate(cs, comps);
    CGContextSetShadowWithColor(ctx, offset, blur, color);
    CGColorRelease(color);
    CGColorSpaceRelease(cs);
}

CGGradientRef makeGradient(const std::vector<RGBA> &stops, const std::vector<double> &locations) {
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    std::vector<CGFloat> comps;
    std::vector<CGFloat> locs;
    comps.reserve(stops.size() * 4);
    for (const RGBA &c : stops) {
        comps.push_back((CGFloat)c.r);
        comps.push_back((CGFloat)c.g);
        comps.push_back((CGFloat)c.b);
        comps.push_back((CGFloat)c.a);
    }
    for (double d : locations) locs.push_back((CGFloat)d);
    CGGradientRef g =
        CGGradientCreateWithColorComponents(cs, comps.data(), locs.data(), stops.size());
    CGColorSpaceRelease(cs);
    return g;
}

CGPathRef makePlatePath() {
    const CGRect r = CGRectMake(kPlateInset, kPlateInset, kGrid - 2 * kPlateInset,
                                kGrid - 2 * kPlateInset);
    return CGPathCreateWithRoundedRect(r, kPlateRadius, kPlateRadius, nullptr);
}

// ---------------------------------------------------------------- colour ---
// The composition is fixed; colour is what varies between treatments. The
// plate, the glyph and the lens are chosen together rather than separately,
// because the only thing that matters is how the three sit against each other.

struct Palette {
    const char *name;
    RGBA plateTop, plateMid, plateBot;  // vertical body gradient
    RGBA plateKey;                      // upper-left key light
    RGBA plateShade;                    // lower-right grounding shade
    RGBA plateRim;                      // rim light along the top edge
    RGBA plateEdge;                     // hairline along the lower edge
    RGBA frameTop, frameBot;            // crop marks — deliberately recessive
    RGBA bodyTop, bodyBot;              // camera body
    RGBA lensTop, lensBot;              // the glass: the focal point
    RGBA catchlight;                    // glint on it
    RGBA glyphShadow;                   // cast by the frame and the camera
    RGBA plateShadow;                   // cast by the plate
};

const Palette kPalettes[] = {
    // Warm plate, ivory glyph, lens sunk into shadow. The plate carries the
    // brand colour and the darkest thing on the icon is the glass.
    {"ember",
     {0.976, 0.420, 0.212, 1.0},
     {0.882, 0.176, 0.157, 1.0},
     {0.588, 0.055, 0.125, 1.0},
     {1.000, 0.925, 0.741, 0.30},
     {0.290, 0.020, 0.070, 0.42},
     {1.000, 0.970, 0.930, 0.55},
     {0.000, 0.000, 0.000, 0.00},
     {1.000, 0.898, 0.855, 0.92},
     {1.000, 0.831, 0.776, 0.92},
     {1.000, 0.976, 0.965, 1.0},
     {1.000, 0.918, 0.890, 1.0},
     {0.353, 0.043, 0.090, 1.0},
     {0.180, 0.016, 0.043, 1.0},
     {1.000, 0.949, 0.914, 0.85},
     {0.353, 0.024, 0.031, 0.34},
     {0.120, 0.020, 0.010, 0.24}},

    // Pale plate, warm glyph. The reference's own weighting, inverted: the
    // colour is in the mark rather than the ground, and the lens goes navy so
    // the darkest point is still the glass.
    {"signal",
     {0.980, 0.980, 0.992, 1.0},
     {0.933, 0.937, 0.953, 1.0},
     {0.859, 0.867, 0.898, 1.0},
     {1.000, 1.000, 1.000, 0.55},
     {0.420, 0.443, 0.510, 0.30},
     {1.000, 1.000, 1.000, 0.90},
     {0.631, 0.647, 0.706, 0.55},
     {1.000, 0.545, 0.373, 1.0},
     {0.937, 0.337, 0.278, 1.0},
     {0.976, 0.400, 0.235, 1.0},
     {0.827, 0.106, 0.176, 1.0},
     {0.204, 0.231, 0.310, 1.0},
     {0.125, 0.145, 0.212, 1.0},
     {1.000, 1.000, 1.000, 0.75},
     {0.549, 0.161, 0.098, 0.28},
     {0.200, 0.208, 0.259, 0.22}},

    // The reference as supplied, plus one saturated element. Everything is the
    // quiet navy-charcoal except the glass, which is the only red on the icon
    // and therefore unmissable.
    {"graphite",
     {0.976, 0.976, 0.988, 1.0},
     {0.929, 0.929, 0.949, 1.0},
     {0.847, 0.855, 0.886, 1.0},
     {1.000, 1.000, 1.000, 0.55},
     {0.420, 0.443, 0.510, 0.30},
     {1.000, 1.000, 1.000, 0.90},
     {0.631, 0.647, 0.706, 0.55},
     {0.365, 0.404, 0.510, 1.0},
     {0.302, 0.341, 0.443, 1.0},
     {0.216, 0.251, 0.341, 1.0},
     {0.137, 0.165, 0.243, 1.0},
     {0.980, 0.361, 0.220, 1.0},
     {0.867, 0.129, 0.161, 1.0},
     {1.000, 0.925, 0.886, 0.80},
     {0.157, 0.176, 0.259, 0.30},
     {0.200, 0.208, 0.259, 0.22}},
};

constexpr size_t kShippingPalette = 1;  // "signal"

/// The shipping colourway, unless SKITCH_ICON_TREATMENT names another one.
const Palette &palette() {
    static const Palette *chosen = nullptr;
    if (!chosen) {
        chosen = &kPalettes[kShippingPalette];
        if (const char *want = std::getenv("SKITCH_ICON_TREATMENT")) {
            for (const Palette &p : kPalettes) {
                if (std::strcmp(p.name, want) == 0) chosen = &p;
            }
        }
    }
    return *chosen;
}

/// Fills the current clip with a top-to-bottom ramp between two colours.
void fillVertical(CGContextRef ctx, RGBA top, RGBA bottom, double y0, double y1) {
    CGGradientRef g = makeGradient({top, bottom}, {0.0, 1.0});
    CGContextDrawLinearGradient(ctx, g, CGPointMake(0, y0), CGPointMake(0, y1),
                                kCGGradientDrawsBeforeStartLocation |
                                    kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g);
}

CGRect circleAt(double cx, double cy, double r) {
    return CGRectMake(cx - r, cy - r, 2 * r, 2 * r);
}

// ------------------------------------------------------------------ plate ---
// The rounded square, lit from the upper left so it reads as an object rather
// than a swatch: a vertical body gradient, a soft key light, a grounding shade
// opposite it, and a rim along the top edge that catches the light.

void drawPlate(CGContextRef ctx, Detail detail, const Palette &P) {
    CGPathRef plate = makePlatePath();
    const double top = kPlateInset, bottom = kGrid - kPlateInset;

    CGContextSaveGState(ctx);
    if (detail == Detail::Full) setShadow(ctx, CGSizeMake(0, 16), 32, P.plateShadow);
    CGContextAddPath(ctx, plate);
    setFill(ctx, P.plateMid);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);

    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, plate);
    CGContextClip(ctx);

    CGGradientRef body = makeGradient({P.plateTop, P.plateMid, P.plateBot}, {0.0, 0.55, 1.0});
    CGContextDrawLinearGradient(ctx, body, CGPointMake(0, top), CGPointMake(0, bottom), 0);
    CGGradientRelease(body);

    CGGradientRef key =
        makeGradient({P.plateKey, {P.plateKey.r, P.plateKey.g, P.plateKey.b, 0.0}}, {0.0, 1.0});
    CGContextDrawRadialGradient(ctx, key, CGPointMake(320, 240), 0, CGPointMake(320, 240), 620, 0);
    CGGradientRelease(key);

    CGGradientRef shade = makeGradient(
        {P.plateShade, {P.plateShade.r, P.plateShade.g, P.plateShade.b, 0.0}}, {0.0, 1.0});
    CGContextDrawRadialGradient(ctx, shade, CGPointMake(930, 1010), 0, CGPointMake(930, 1010), 830,
                                0);
    CGGradientRelease(shade);
    CGContextRestoreGState(ctx);

    if (detail == Detail::Full || detail == Detail::Small) {
        // Rim light on the top edge and, for pale plates, a hairline along the
        // bottom so the icon still has an outline against a white background.
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, plate);
        CGContextClip(ctx);
        CGContextAddPath(ctx, plate);
        CGContextSetLineWidth(ctx, 8.0);
        CGContextReplacePathWithStrokedPath(ctx);
        CGContextClip(ctx);

        CGGradientRef rim =
            makeGradient({P.plateRim, {P.plateRim.r, P.plateRim.g, P.plateRim.b, 0.0}}, {0.0, 1.0});
        CGContextDrawLinearGradient(ctx, rim, CGPointMake(0, top), CGPointMake(0, top + 460), 0);
        CGGradientRelease(rim);

        if (P.plateEdge.a > 0.0) {
            CGGradientRef edge = makeGradient(
                {P.plateEdge, {P.plateEdge.r, P.plateEdge.g, P.plateEdge.b, 0.0}}, {0.0, 1.0});
            CGContextDrawLinearGradient(ctx, edge, CGPointMake(0, bottom),
                                        CGPointMake(0, bottom - 520), 0);
            CGGradientRelease(edge);
        }
        CGContextRestoreGState(ctx);
    }

    CGPathRelease(plate);
}

// ------------------------------------------------------------------ glyph ---
// A capture frame with a camera in it. The four corner marks say "choose a
// region"; the camera says what happens when you have. They are one object:
// drawn into a single transparency layer, sharing one gradient and one shadow,
// with the lens punched clean through the body so the plate shows in the gap.

struct Geom {
    bool frame;
    double frameHalf, arm, frameWidth;      // crop marks
    double bodyW, bodyH, bodyR, cameraY;    // camera body
    double humpW, humpH, humpR, humpX;      // viewfinder hump on the top edge
    double lensOuter, lensGap, catchR;      // the glass, and the glint on it
    double shadowDY, shadowBlur;
};

/// Two objects cannot share sixteen pixels. Below 64px the frame goes and the
/// camera grows into the space it leaves, which keeps one clear silhouette
/// instead of two mushy ones.
Geom geometryFor(Detail detail) {
    switch (detail) {
        case Detail::Nano:
            return {false, 0, 0, 0, 528, 372, 76, 536, 172, 60, 18, -122, 110, 0, 0, 0, 0};
        case Detail::Micro:
            return {false, 0, 0, 0, 470, 336, 68, 534, 152, 52, 16, -106, 114, 26, 0, 0, 0};
        case Detail::Small:
            return {true, 262, 118, 54, 366, 258, 66, 528, 130, 42, 16, -74, 92, 22, 0, 0, 0};
        case Detail::Full:
            return {true, 264, 122, 47, 356, 250, 64, 526, 128, 40, 16, -70, 87, 22, 15, 10, 20};
    }
    return geometryFor(Detail::Full);
}

CGPathRef makeFramePath(const Geom &g) {
    const double c = kGrid / 2;
    const double xs[2] = {c - g.frameHalf, c + g.frameHalf};
    const double ys[2] = {c - g.frameHalf, c + g.frameHalf};
    CGMutablePathRef p = CGPathCreateMutable();
    for (int iy = 0; iy < 2; ++iy) {
        for (int ix = 0; ix < 2; ++ix) {
            const double dx = ix == 0 ? g.arm : -g.arm;
            const double dy = iy == 0 ? g.arm : -g.arm;
            CGPathMoveToPoint(p, nullptr, xs[ix], ys[iy] + dy);
            CGPathAddLineToPoint(p, nullptr, xs[ix], ys[iy]);
            CGPathAddLineToPoint(p, nullptr, xs[ix] + dx, ys[iy]);
        }
    }
    return p;
}

CGPathRef makeCameraPath(const Geom &g) {
    const double cx = kGrid / 2;
    const CGRect body =
        CGRectMake(cx - g.bodyW / 2, g.cameraY - g.bodyH / 2, g.bodyW, g.bodyH);

    CGMutablePathRef p = CGPathCreateMutable();
    CGPathRef bodyPath = CGPathCreateWithRoundedRect(body, g.bodyR, g.bodyR, nullptr);
    CGPathAddPath(p, nullptr, bodyPath);
    CGPathRelease(bodyPath);

    // The hump runs a corner radius deep into the body so the two fill as one
    // shape under the nonzero winding rule, with no seam between them.
    const CGRect hump = CGRectMake(cx + g.humpX - g.humpW / 2, body.origin.y - g.humpH, g.humpW,
                                   g.humpH + g.bodyR);
    CGPathRef humpPath = CGPathCreateWithRoundedRect(hump, g.humpR, g.humpR, nullptr);
    CGPathAddPath(p, nullptr, humpPath);
    CGPathRelease(humpPath);
    return p;
}

void drawGlyph(CGContextRef ctx, Detail detail, const Palette &P, const Geom &g) {
    const double cx = kGrid / 2;
    const double top = g.cameraY - g.bodyH / 2 - g.humpH;
    const double bottom = g.cameraY + g.bodyH / 2;

    CGContextSaveGState(ctx);
    if (g.shadowBlur > 0) setShadow(ctx, CGSizeMake(0, g.shadowDY), g.shadowBlur, P.glyphShadow);
    CGContextBeginTransparencyLayer(ctx, nullptr);

    if (g.frame) {
        CGPathRef marks = makeFramePath(g);
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, marks);
        CGContextSetLineWidth(ctx, g.frameWidth);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        CGContextReplacePathWithStrokedPath(ctx);
        CGContextClip(ctx);
        fillVertical(ctx, P.frameTop, P.frameBot, kGrid / 2 - g.frameHalf,
                     kGrid / 2 + g.frameHalf);
        CGContextRestoreGState(ctx);
        CGPathRelease(marks);
    }

    CGPathRef camera = makeCameraPath(g);
    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, camera);
    CGContextClip(ctx);
    fillVertical(ctx, P.bodyTop, P.bodyBot, top, bottom);
    CGContextRestoreGState(ctx);
    CGPathRelease(camera);

    if (g.lensGap > 0) {
        CGContextSaveGState(ctx);
        CGContextSetBlendMode(ctx, kCGBlendModeDestinationOut);
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
        CGContextFillEllipseInRect(ctx, circleAt(cx, g.cameraY, g.lensOuter));
        CGContextRestoreGState(ctx);
    }

    CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);

    // The glass, dropped into the hole the knockout just made.
    const double r = g.lensOuter - g.lensGap;
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, circleAt(cx, g.cameraY, r));
    CGContextClip(ctx);
    fillVertical(ctx, P.lensTop, P.lensBot, g.cameraY - r, g.cameraY + r);
    CGContextRestoreGState(ctx);

    if (g.catchR > 0) {
        setFill(ctx, P.catchlight);
        CGContextFillEllipseInRect(ctx, circleAt(cx - r * 0.33, g.cameraY - r * 0.35, g.catchR));
    }
}

CGImageRef renderIcon(size_t pixels) {
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx =
        CGBitmapContextCreate(nullptr, pixels, pixels, 8, 0, cs,
                              kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(cs);
    if (!ctx) return nullptr;

    CGContextSetShouldAntialias(ctx, true);
    CGContextSetAllowsAntialiasing(ctx, true);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);

    // y downwards, and the 1024pt design grid scaled to this output size.
    const double s = pixels / kGrid;
    CGContextTranslateCTM(ctx, 0, pixels);
    CGContextScaleCTM(ctx, 1, -1);
    CGContextScaleCTM(ctx, s, s);

    const Detail detail = detailFor(pixels);
    const Palette &P = palette();
    drawPlate(ctx, detail, P);
    drawGlyph(ctx, detail, P, geometryFor(detail));

    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}

struct Variant {
    const char *name;   // .iconset filename
    const char *osType; // ICNS chunk type
    size_t pixels;
};

// The ten entries iconutil emits, with the OSType each maps to. All are stored
// as PNG, which every macOS since 10.7 reads.
const Variant kVariants[] = {
    {"icon_16x16.png",      "icp4", 16},
    {"icon_16x16@2x.png",   "ic11", 32},
    {"icon_32x32.png",      "icp5", 32},
    {"icon_32x32@2x.png",   "ic12", 64},
    {"icon_128x128.png",    "ic07", 128},
    {"icon_128x128@2x.png", "ic13", 256},
    {"icon_256x256.png",    "ic08", 256},
    {"icon_256x256@2x.png", "ic14", 512},
    {"icon_512x512.png",    "ic09", 512},
    {"icon_512x512@2x.png", "ic10", 1024},
};
constexpr size_t kVariantCount = sizeof(kVariants) / sizeof(kVariants[0]);

NSData *encodePNG(CGImageRef image) {
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
    CGImageDestinationRef dest =
        CGImageDestinationCreateWithData(data, CFSTR("public.png"), 1, nullptr);
    if (!dest) {
        CFRelease(data);
        return nil;
    }
    CGImageDestinationAddImage(dest, image, nullptr);
    const bool ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    if (!ok) {
        CFRelease(data);
        return nil;
    }
    return (__bridge_transfer NSData *)data;
}

void appendUInt32BE(NSMutableData *out, uint32_t value) {
    const uint8_t bytes[4] = {
        static_cast<uint8_t>((value >> 24) & 0xFF), static_cast<uint8_t>((value >> 16) & 0xFF),
        static_cast<uint8_t>((value >> 8) & 0xFF),  static_cast<uint8_t>(value & 0xFF),
    };
    [out appendBytes:bytes length:4];
}

/// Builds the .icns container: an 'icns' magic, the total byte count, then one
/// {OSType, length, PNG} chunk per size. iconutil produces the same layout, but
/// writing it here keeps the build free of an external tool.
NSData *buildICNS(NSArray<NSData *> *pngs) {
    NSMutableData *body = [NSMutableData data];
    for (size_t i = 0; i < kVariantCount; ++i) {
        NSData *png = pngs[i];
        [body appendBytes:kVariants[i].osType length:4];
        appendUInt32BE(body, static_cast<uint32_t>(8 + png.length));
        [body appendData:png];
    }

    NSMutableData *out = [NSMutableData data];
    [out appendBytes:"icns" length:4];
    appendUInt32BE(out, static_cast<uint32_t>(8 + body.length));
    [out appendData:body];
    return out;
}

}  // namespace

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            std::fputs("usage: skitch_iconmaker <output.icns> [output.iconset dir]\n",
                       stderr);
            return 2;
        }

        NSString *icnsPath = @(argv[1]);
        NSString *iconsetDir = argc > 2 ? @(argv[2]) : nil;
        NSError *error = nil;

        if (iconsetDir &&
            ![[NSFileManager defaultManager] createDirectoryAtPath:iconsetDir
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            std::fprintf(stderr, "iconmaker: cannot create %s: %s\n", argv[2],
                         error.localizedDescription.UTF8String);
            return 1;
        }

        NSMutableArray<NSData *> *pngs = [NSMutableArray array];
        for (const Variant &v : kVariants) {
            CGImageRef img = renderIcon(v.pixels);
            if (!img) {
                std::fprintf(stderr, "iconmaker: render failed for %s\n", v.name);
                return 1;
            }
            NSData *png = encodePNG(img);
            CGImageRelease(img);
            if (!png) {
                std::fprintf(stderr, "iconmaker: PNG encode failed for %s\n", v.name);
                return 1;
            }
            [pngs addObject:png];

            if (iconsetDir) {
                NSString *path = [iconsetDir stringByAppendingPathComponent:@(v.name)];
                if (![png writeToFile:path atomically:NO]) {
                    std::fprintf(stderr, "iconmaker: cannot write %s\n", v.name);
                    return 1;
                }
            }
        }

        NSData *icns = buildICNS(pngs);
        if (![icns writeToFile:icnsPath atomically:NO]) {
            std::fprintf(stderr, "iconmaker: cannot write %s\n", argv[1]);
            return 1;
        }

        std::printf("iconmaker: wrote %s (%zu sizes, %.1f KB)\n", argv[1], kVariantCount,
                    icns.length / 1024.0);
        return 0;
    }
}
