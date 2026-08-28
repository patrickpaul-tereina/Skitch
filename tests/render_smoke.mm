// Headless exercise of the document model and renderer. Builds a synthetic
// "screenshot", marks it up with every tool, crops it, round-trips undo/redo
// and writes the flattened result to disk.
//
//   ./skitch_render_smoke /tmp/out.png

#import <Foundation/Foundation.h>

#include <cassert>
#include <cstdio>

#include "model/Document.h"
#include "render/Renderer.h"
#include "util/ImageIO.h"

using namespace sk;

namespace {

int gFailures = 0;

void check(bool cond, const char *what) {
    if (cond) {
        std::printf("  ok    %s\n", what);
    } else {
        std::printf("  FAIL  %s\n", what);
        ++gFailures;
    }
}

/// A stand-in for a captured screen: gradient plus some hard edges so the
/// pixelate tool has something to chew on.
CGImageRef makeFakeScreenshot(size_t w, size_t h) {
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(nullptr, w, h, 8, 0, cs,
                                             kCGImageAlphaPremultipliedFirst |
                                                 kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(cs);
    if (!ctx) return nullptr;

    CGContextSetRGBFillColor(ctx, 0.97, 0.97, 0.98, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, w, h));

    CGContextSetRGBFillColor(ctx, 0.20, 0.24, 0.32, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, h - 90, w, 90));  // title bar

    for (int i = 0; i < 12; ++i) {
        CGContextSetRGBFillColor(ctx, 0.55 + i * 0.03, 0.62, 0.78, 1.0);
        CGContextFillRect(ctx, CGRectMake(60 + i * 90, 140, 62, h - 300));
    }

    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}

Annotation base(Tool t, double lw = 8.0) {
    Annotation a;
    a.tool = t;
    a.lineWidth = lw;
    a.stroke = Color(0.93, 0.16, 0.16, 1.0);
    a.fill = Color(0.93, 0.16, 0.16, 0.22);
    return a;
}

}  // namespace

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        const char *outPath = argc > 1 ? argv[1] : "skitch_smoke.png";

        const size_t W = 1200, H = 800;
        CGImageRef shot = makeFakeScreenshot(W, H);
        check(shot != nullptr, "synthetic screenshot created");
        if (!shot) return 1;

        Document doc;
        doc.reset(W, H);
        check(doc.width() == W && doc.height() == H, "document sized to image");

        // ---- every tool -------------------------------------------------
        Annotation arrow = base(Tool::Arrow, 10);
        arrow.p0 = Vec2(120, 620);
        arrow.p1 = Vec2(430, 300);
        doc.add(arrow);

        Annotation line = base(Tool::Line, 6);
        line.stroke = Color(0.16, 0.50, 0.95, 1.0);
        line.p0 = Vec2(500, 640);
        line.p1 = Vec2(900, 640);
        doc.add(line);

        Annotation rect = base(Tool::Rect, 6);
        rect.stroke = Color(0.20, 0.72, 0.35, 1.0);
        rect.p0 = Vec2(470, 200);
        rect.p1 = Vec2(700, 380);
        doc.add(rect);

        Annotation ell = base(Tool::Ellipse, 6);
        ell.filled = true;
        ell.fill = Color(1.0, 0.62, 0.06, 0.30);
        ell.stroke = Color(1.0, 0.62, 0.06, 1.0);
        ell.p0 = Vec2(740, 200);
        ell.p1 = Vec2(980, 390);
        doc.add(ell);

        Annotation pen = base(Tool::Pen, 5);
        pen.stroke = Color(0.60, 0.15, 0.75, 1.0);
        for (int i = 0; i <= 60; ++i) {
            const double t = i / 60.0;
            pen.points.push_back(Vec2(150 + t * 300, 720 - std::sin(t * 6.0) * 40.0));
        }
        doc.add(pen);

        Annotation hl = base(Tool::Highlighter, 8);
        hl.stroke = Color(0.99, 0.90, 0.20, 1.0);
        hl.points.push_back(Vec2(620, 700));
        hl.points.push_back(Vec2(1040, 700));
        doc.add(hl);

        Annotation text = base(Tool::Text);
        text.fontSize = 44;
        text.stroke = Color(0.10, 0.10, 0.12, 1.0);
        text.p0 = Vec2(120, 90);
        text.text = "Look here\nsecond line";
        const int textID = doc.add(text);

        Annotation pix = base(Tool::Pixelate);
        pix.blockSize = 18;
        pix.p0 = Vec2(300, 430);
        pix.p1 = Vec2(620, 560);
        doc.add(pix);

        check(doc.count() == 8, "eight annotations added");

        // ---- measurement + hit testing ----------------------------------
        const Annotation *t2 = doc.find(textID);
        measureText(*t2);
        check(t2->measuredWidth > 0 && t2->measuredHeight > 0, "text measured");
        check(t2->measuredHeight > t2->fontSize * 2.0, "two text lines measured");

        check(doc.hitTest(Vec2(430, 300), 4.0) != 0, "hit test finds the arrow tip");
        check(doc.hitTest(Vec2(1190, 12), 4.0) == 0, "hit test misses empty area");
        check(doc.hitTest(Vec2(860, 295), 4.0) != 0, "hit test finds the filled ellipse");

        // ---- z-order -----------------------------------------------------
        const int firstID = doc.items().front().id;
        doc.raise(firstID);
        check(doc.items()[1].id == firstID, "raise moves an item up one slot");
        doc.lower(firstID);
        check(doc.items().front().id == firstID, "lower puts it back");

        // ---- undo / redo across a crop -----------------------------------
        doc.beginUndoGroup();
        doc.applyCrop(RectD(80, 40, 1000, 700));
        check(doc.width() == 1000 && doc.height() == 700, "crop resizes the document");
        check(doc.cropRect().x == 80, "crop offset recorded in base coordinates");

        doc.undo();
        check(doc.width() == W, "undo restores the full frame");
        doc.redo();
        check(doc.width() == 1000, "redo re-applies the crop");

        // Compose a second crop onto the first.
        doc.beginUndoGroup();
        doc.applyCrop(RectD(20, 20, 900, 640));
        check(doc.cropRect().x == 100, "crops compose in base coordinates");
        doc.undo();

        // ---- translate / resize ------------------------------------------
        Annotation *movable = doc.find(textID);
        const Vec2 before = movable->p0;
        movable->translate(Vec2(10, -5));
        check(movable->p0.x == before.x + 10 && movable->p0.y == before.y - 5,
              "translate offsets the annotation");
        movable->translate(Vec2(-10, 5));

        Annotation *r = doc.find(doc.items()[2].id);
        const RectD from = r->coreBounds();
        r->transformFromRectToRect(from, RectD(from.x, from.y, from.w * 2, from.h * 2));
        check(std::fabs(r->coreBounds().w - from.w * 2) < 0.01, "resize scales geometry");
        r->transformFromRectToRect(r->coreBounds(), from);

        // ---- rollback ------------------------------------------------------
        {
            Document d;
            d.reset(400, 300);
            check(!d.hasEdits(), "a fresh document reports no edits");

            Annotation a = base(Tool::Rect);
            a.p0 = Vec2(10, 10);
            a.p1 = Vec2(100, 80);
            d.beginUndoGroup();
            d.add(a);
            check(d.hasEdits(), "adding a mark counts as an edit");

            d.beginUndoGroup();
            d.applyCrop(RectD(5, 5, 200, 150));

            // Revert clears marks and crop together, as one undoable step.
            d.beginUndoGroup();
            d.revert();
            check(d.count() == 0, "revert drops every mark");
            check(d.width() == 400 && d.height() == 300, "revert restores the full frame");
            check(!d.hasEdits(), "reverted document reports no edits");

            d.undo();
            check(d.count() == 1 && d.width() == 200, "revert is undoable in one step");

            // A crop alone, with no marks, must still register as an edit.
            Document e;
            e.reset(400, 300);
            e.beginUndoGroup();
            e.applyCrop(RectD(0, 0, 200, 300));
            check(e.hasEdits(), "a crop alone counts as an edit");
            e.beginUndoGroup();
            e.revert();
            check(!e.hasEdits(), "revert undoes a crop-only edit");
        }

        // A cancelled gesture (begin then abort) must not eat the redo stack.
        {
            Document d;
            d.reset(400, 300);
            Annotation a = base(Tool::Line);
            a.p0 = Vec2(0, 0);
            a.p1 = Vec2(50, 50);
            d.beginUndoGroup();
            d.add(a);
            d.undo();
            check(d.canRedo(), "redo available after an undo");

            d.beginUndoGroup();   // e.g. a click that selected but moved nothing
            d.abortUndoGroup();
            check(d.canRedo(), "an aborted gesture preserves the redo stack");
            d.redo();
            check(d.count() == 1, "redo still works after an aborted gesture");
        }

        // ---- render -------------------------------------------------------
        CGImageRef flat = renderToImage(doc, shot);
        check(flat != nullptr, "flattened image produced");
        if (flat) {
            check(CGImageGetWidth(flat) == 1000 && CGImageGetHeight(flat) == 700,
                  "flattened image matches the crop size");

            NSURL *url = [NSURL fileURLWithPath:@(outPath)];
            NSError *err = nil;
            check(SKWriteImage(flat, url, &err), "PNG written");

            CGImageRef reread = SKReadImage(url);
            check(reread != nullptr, "PNG reads back");
            if (reread) {
                check(CGImageGetWidth(reread) == 1000, "round-tripped size matches");
                CGImageRelease(reread);
            }
            CGImageRelease(flat);
        }

        // Full-frame render for eyeballing every tool at once.
        doc.resetCrop();
        CGImageRef full = renderToImage(doc, shot);
        if (full) {
            NSString *fullPath =
                [@(outPath) stringByReplacingOccurrencesOfString:@".png"
                                                      withString:@"-full.png"];
            NSError *err = nil;
            check(SKWriteImage(full, [NSURL fileURLWithPath:fullPath], &err),
                  "full-frame PNG written");
            CGImageRelease(full);
            std::printf("\nwrote %s\n", fullPath.UTF8String);
        }

        CGImageRelease(shot);

        std::printf("\n%s (%d failure%s)\n", gFailures == 0 ? "PASS" : "FAIL", gFailures,
                    gFailures == 1 ? "" : "s");
        return gFailures == 0 ? 0 : 1;
    }
}
