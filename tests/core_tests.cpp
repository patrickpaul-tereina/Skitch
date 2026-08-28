// Tests for the portable document model. Deliberately free of any platform
// header so it compiles and runs on macOS, Linux and Windows — this is the
// suite that keeps `skitch_core` honest about being platform-free.
//
//   ./skitch_core_tests

#include <cmath>
#include <cstddef>
#include <cstdio>
#include <string>

#include "model/Annotation.h"
#include "model/Document.h"
#include "model/Types.h"

using namespace sk;

namespace {

int gChecks = 0;
int gFailures = 0;

void check(bool cond, const char *what) {
    ++gChecks;
    if (!cond) {
        std::printf("  FAIL  %s\n", what);
        ++gFailures;
    }
}

void section(const char *name) { std::printf("\n%s\n", name); }

bool nearly(double a, double b, double tol = 1e-6) { return std::fabs(a - b) <= tol; }

Annotation make(Tool t, Vec2 a, Vec2 b, double lw = 8.0) {
    Annotation ann;
    ann.tool = t;
    ann.p0 = a;
    ann.p1 = b;
    ann.lineWidth = lw;
    return ann;
}

// ------------------------------------------------------------------ geometry

void testGeometry() {
    section("geometry");

    check(nearly(Vec2(3, 4).length(), 5.0), "Vec2::length");
    check(nearly(Vec2(3, 4).normalized().length(), 1.0), "Vec2::normalized is unit length");
    check(Vec2(0, 0).normalized().length() == 0.0, "normalizing a zero vector is safe");

    const Vec2 p = Vec2(2, 0).perp();
    check(nearly(p.x, 0.0) && nearly(p.y, 2.0), "Vec2::perp rotates 90 degrees");

    const RectD r = RectD::fromCorners(Vec2(30, 40), Vec2(10, 20));
    check(nearly(r.x, 10) && nearly(r.y, 20) && nearly(r.w, 20) && nearly(r.h, 20),
          "RectD::fromCorners normalises reversed corners");

    check(RectD(0, 0, 10, 10).contains(Vec2(5, 5)), "RectD::contains inside");
    check(!RectD(0, 0, 10, 10).contains(Vec2(15, 5)), "RectD::contains outside");

    const RectD i = RectD(0, 0, 10, 10).intersect(RectD(5, 5, 10, 10));
    check(nearly(i.x, 5) && nearly(i.w, 5), "RectD::intersect overlapping");
    check(RectD(0, 0, 10, 10).intersect(RectD(50, 50, 5, 5)).isEmpty(),
          "RectD::intersect disjoint is empty");

    const RectD u = RectD(0, 0, 10, 10).unionWith(RectD(20, 20, 10, 10));
    check(nearly(u.w, 30) && nearly(u.h, 30), "RectD::unionWith spans both");
    check(nearly(RectD().unionWith(RectD(1, 2, 3, 4)).w, 3.0),
          "union with an empty rect returns the other");

    check(nearly(distanceToSegment(Vec2(5, 5), Vec2(0, 0), Vec2(10, 0)), 5.0),
          "distanceToSegment perpendicular");
    check(nearly(distanceToSegment(Vec2(-5, 0), Vec2(0, 0), Vec2(10, 0)), 5.0),
          "distanceToSegment clamps past the start");
    check(nearly(distanceToSegment(Vec2(3, 4), Vec2(0, 0), Vec2(0, 0)), 5.0),
          "distanceToSegment on a degenerate segment");

    check(clampd(5, 0, 10) == 5 && clampd(-1, 0, 10) == 0 && clampd(99, 0, 10) == 10,
          "clampd");
}

// ---------------------------------------------------------------- annotations

void testAnnotationBounds() {
    section("annotation bounds");

    Annotation rect = make(Tool::Rect, Vec2(10, 10), Vec2(110, 60));
    check(nearly(rect.coreBounds().w, 100) && nearly(rect.coreBounds().h, 50),
          "box coreBounds");
    check(rect.displayBounds().w > rect.coreBounds().w,
          "displayBounds pads for stroke width");

    Annotation arrow = make(Tool::Arrow, Vec2(0, 0), Vec2(100, 0), 10);
    check(arrow.displayBounds().h > arrow.coreBounds().h + 10,
          "arrow displayBounds leaves room for the head");

    Annotation pen;
    pen.tool = Tool::Pen;
    pen.points.push_back(Vec2(10, 10));
    pen.points.push_back(Vec2(50, 90));
    pen.points.push_back(Vec2(30, 40));
    const RectD pb = pen.coreBounds();
    check(nearly(pb.x, 10) && nearly(pb.y, 10) && nearly(pb.w, 40) && nearly(pb.h, 80),
          "freehand coreBounds spans every point");

    Annotation empty;
    empty.tool = Tool::Pen;
    check(empty.coreBounds().isEmpty(), "an empty freehand stroke has empty bounds");

    // Without a renderer to measure it, text falls back to an estimate rather
    // than reporting nothing.
    Annotation text;
    text.tool = Tool::Text;
    text.fontSize = 20;
    text.text = "hello";
    check(text.coreBounds().w > 0 && text.coreBounds().h > 0,
          "unmeasured text still reports usable bounds");

    check(rect.isBoxLike() && !rect.isLineLike() && !rect.isFreehand(), "rect classified");
    check(arrow.isLineLike() && !arrow.isBoxLike(), "arrow classified");
    check(pen.isFreehand(), "pen classified");
    check(toolCreatesAnnotation(Tool::Arrow), "arrow creates an annotation");
    check(!toolCreatesAnnotation(Tool::Select), "select does not");
    check(!toolCreatesAnnotation(Tool::Crop), "crop does not");
}

void testHitTesting() {
    section("hit testing");

    Annotation line = make(Tool::Line, Vec2(0, 0), Vec2(100, 0), 6);
    check(line.hitTest(Vec2(50, 0), 2.0), "line hit on the segment");
    check(!line.hitTest(Vec2(50, 60), 2.0), "line miss far away");
    check(!line.hitTest(Vec2(-40, 0), 2.0), "line miss past the end");

    Annotation hollow = make(Tool::Rect, Vec2(0, 0), Vec2(100, 100), 4);
    check(hollow.hitTest(Vec2(0, 50), 3.0), "outlined rect hit on the edge");
    check(!hollow.hitTest(Vec2(50, 50), 3.0), "outlined rect misses the hollow centre");

    Annotation filled = make(Tool::Rect, Vec2(0, 0), Vec2(100, 100), 4);
    filled.filled = true;
    check(filled.hitTest(Vec2(50, 50), 3.0), "filled rect hit in the centre");

    Annotation ring = make(Tool::Ellipse, Vec2(0, 0), Vec2(100, 100), 4);
    check(ring.hitTest(Vec2(50, 0), 4.0), "outlined ellipse hit on the rim");
    check(!ring.hitTest(Vec2(50, 50), 4.0), "outlined ellipse misses the centre");
    check(!ring.hitTest(Vec2(0, 0), 4.0), "outlined ellipse misses the bounding corner");

    Annotation disc = ring;
    disc.filled = true;
    check(disc.hitTest(Vec2(50, 50), 4.0), "filled ellipse hit in the centre");

    Annotation pen;
    pen.tool = Tool::Pen;
    pen.lineWidth = 4;
    pen.points.push_back(Vec2(0, 0));
    pen.points.push_back(Vec2(100, 0));
    check(pen.hitTest(Vec2(50, 1), 2.0), "freehand hit near the path");
    check(!pen.hitTest(Vec2(50, 80), 2.0), "freehand miss");

    Annotation dot;
    dot.tool = Tool::Pen;
    dot.lineWidth = 10;
    dot.points.push_back(Vec2(20, 20));
    check(dot.hitTest(Vec2(21, 21), 2.0), "single-point freehand is still hittable");

    Annotation pix = make(Tool::Pixelate, Vec2(0, 0), Vec2(50, 50));
    check(pix.hitTest(Vec2(25, 25), 1.0), "pixelate hit anywhere inside");
}

void testTransforms() {
    section("transforms");

    Annotation a = make(Tool::Line, Vec2(10, 10), Vec2(20, 30));
    a.translate(Vec2(5, -5));
    check(nearly(a.p0.x, 15) && nearly(a.p0.y, 5) && nearly(a.p1.x, 25),
          "translate moves both endpoints");

    Annotation pen;
    pen.tool = Tool::Pen;
    pen.points.push_back(Vec2(0, 0));
    pen.points.push_back(Vec2(10, 10));
    pen.translate(Vec2(3, 4));
    check(nearly(pen.points[1].x, 13) && nearly(pen.points[1].y, 14),
          "translate moves every freehand point");

    Annotation box = make(Tool::Rect, Vec2(0, 0), Vec2(100, 100), 10);
    const RectD from = box.coreBounds();
    box.transformFromRectToRect(from, RectD(0, 0, 200, 200));
    check(nearly(box.coreBounds().w, 200), "transform scales geometry");
    check(box.lineWidth > 10.0, "transform scales stroke width with the shape");

    Annotation txt;
    txt.tool = Tool::Text;
    txt.fontSize = 20;
    txt.p0 = Vec2(0, 0);
    txt.measuredWidth = 100;
    txt.measuredHeight = 25;
    txt.transformFromRectToRect(RectD(0, 0, 100, 25), RectD(0, 0, 200, 50));
    check(nearly(txt.fontSize, 40), "transform scales font size instead of stroke width");
    check(txt.measuredWidth == 0.0, "transform invalidates the cached text measurement");

    // A degenerate source rect must not divide by zero.
    Annotation safe = make(Tool::Rect, Vec2(5, 5), Vec2(5, 5));
    safe.transformFromRectToRect(RectD(0, 0, 0, 0), RectD(0, 0, 10, 10));
    check(nearly(safe.p0.x, 5), "transform from an empty rect is a no-op");
}

// -------------------------------------------------------------------- document

void testDocumentBasics() {
    section("document basics");

    Document d;
    d.reset(800, 600);
    check(nearly(d.width(), 800) && nearly(d.height(), 600), "reset sizes the document");
    check(nearly(d.baseWidth(), 800), "reset records the base size");
    check(d.count() == 0, "reset clears annotations");
    check(!d.isDirty(), "a fresh document is clean");
    check(!d.canUndo() && !d.canRedo(), "a fresh document has no history");

    const int id = d.add(make(Tool::Rect, Vec2(10, 10), Vec2(50, 50)));
    check(id != 0, "add returns an id");
    check(d.count() == 1, "add appends");
    check(d.isDirty(), "add marks the document dirty");
    check(d.find(id) != nullptr, "find locates by id");
    check(d.find(9999) == nullptr, "find misses an unknown id");

    const int id2 = d.add(make(Tool::Line, Vec2(0, 0), Vec2(5, 5)));
    check(id2 != id, "ids are unique");

    d.markClean();
    check(!d.isDirty(), "markClean clears the flag");

    check(d.remove(id), "remove succeeds for a known id");
    check(!d.remove(id), "remove fails the second time");
    check(d.count() == 1, "remove drops exactly one");

    d.clear();
    check(d.count() == 0, "clear empties the document");
}

void testDocumentHitAndOrder() {
    section("document hit testing and z-order");

    Document d;
    d.reset(400, 400);
    const int lower = d.add(make(Tool::Rect, Vec2(0, 0), Vec2(200, 200), 4));
    const int upper = d.add(make(Tool::Rect, Vec2(0, 0), Vec2(200, 200), 4));

    check(d.hitTest(Vec2(0, 100), 4.0) == upper, "hit test returns the topmost match");
    check(d.hitTest(Vec2(390, 390), 4.0) == 0, "hit test returns 0 for empty space");

    check(d.lower(upper), "lower moves an item down");
    check(d.items().front().id == upper, "lowered item is now first");
    check(!d.lower(upper), "lowering the bottom item is a no-op");

    check(d.raise(upper), "raise moves an item up");
    check(d.items().back().id == upper, "raised item is now last");
    check(!d.raise(upper), "raising the top item is a no-op");

    check(!d.raise(9999) && !d.lower(9999), "reordering an unknown id fails");
    (void)lower;
}

void testCrop() {
    section("crop");

    Document d;
    d.reset(1000, 800);
    check(!d.hasEdits(), "an untouched document reports no edits");

    d.applyCrop(RectD(100, 50, 400, 300));
    check(nearly(d.width(), 400) && nearly(d.height(), 300), "crop resizes the document");
    check(nearly(d.cropRect().x, 100), "crop origin is in base coordinates");
    check(d.hasEdits(), "a crop counts as an edit");

    // A second crop is expressed in the cropped document's own coordinates.
    d.applyCrop(RectD(50, 50, 100, 100));
    check(nearly(d.cropRect().x, 150) && nearly(d.cropRect().y, 100),
          "crops compose into base coordinates");

    // Coordinate mapping either way.
    const Vec2 base = d.toBase(Vec2(10, 10));
    check(nearly(base.x, 160) && nearly(base.y, 110), "toBase offsets by the crop origin");
    const Vec2 back = d.fromBase(base);
    check(nearly(back.x, 10) && nearly(back.y, 10), "fromBase is the inverse");

    d.resetCrop();
    check(nearly(d.width(), 1000), "resetCrop restores the full frame");

    // Out-of-bounds crops are clamped, and degenerate ones rejected.
    d.applyCrop(RectD(900, 700, 500, 500));
    check(nearly(d.cropRect().w, 100) && nearly(d.cropRect().h, 100),
          "crop is clamped to the base image");

    Document e;
    e.reset(100, 100);
    e.applyCrop(RectD(200, 200, 50, 50));
    check(nearly(e.width(), 100), "a fully out-of-bounds crop is ignored");
    e.applyCrop(RectD(0, 0, 0.4, 0.4));
    check(nearly(e.width(), 100), "a sub-pixel crop is ignored");
}

void testUndo() {
    section("undo and redo");

    Document d;
    d.reset(400, 300);

    d.beginUndoGroup();
    const int a = d.add(make(Tool::Rect, Vec2(0, 0), Vec2(10, 10)));
    check(d.canUndo(), "an edit makes undo available");

    d.undo();
    check(d.count() == 0, "undo removes the added annotation");
    check(d.canRedo(), "undo makes redo available");

    d.redo();
    check(d.count() == 1, "redo restores it");
    check(d.find(a) != nullptr, "redo restores the same id");

    // Undo spanning a crop, which is state rather than an annotation.
    d.beginUndoGroup();
    d.applyCrop(RectD(10, 10, 100, 100));
    d.undo();
    check(nearly(d.width(), 400), "undo reverts a crop");

    // A fresh edit clears the redo stack.
    d.beginUndoGroup();
    d.add(make(Tool::Line, Vec2(0, 0), Vec2(1, 1)));
    check(!d.canRedo(), "a new edit discards the redo stack");

    // ...but an aborted gesture must not.
    d.undo();
    check(d.canRedo(), "redo available after undo");
    d.beginUndoGroup();
    d.abortUndoGroup();
    check(d.canRedo(), "an aborted gesture preserves the redo stack");
    d.redo();
    check(d.count() == 2, "redo still works after an aborted gesture");

    // Abort restores the pre-gesture state.
    const std::size_t before = d.count();
    d.beginUndoGroup();
    d.add(make(Tool::Line, Vec2(0, 0), Vec2(2, 2)));
    d.abortUndoGroup();
    check(d.count() == before, "abort rolls back the mutation");

    // Undo and redo on an exhausted stack are no-ops, not crashes.
    Document e;
    e.reset(10, 10);
    e.undo();
    e.redo();
    check(e.count() == 0, "undo/redo with no history is safe");
}

void testUndoDepth() {
    section("undo depth");

    Document d;
    d.reset(100, 100);
    // More edits than the history can hold; the oldest fall off the back.
    for (int i = 0; i < 200; ++i) {
        d.beginUndoGroup();
        d.add(make(Tool::Line, Vec2(0, 0), Vec2(1, 1)));
    }
    check(d.count() == 200, "all edits applied");

    int undone = 0;
    while (d.canUndo()) {
        d.undo();
        ++undone;
        if (undone > 500) break;  // guard against a runaway loop
    }
    check(undone > 0 && undone <= 200, "undo history is bounded and terminates");
    check(d.count() > 0, "the oldest states fell off, so it does not unwind to empty");
}

void testRevert() {
    section("revert");

    Document d;
    d.reset(500, 400);
    check(!d.hasEdits(), "nothing to revert initially");

    d.beginUndoGroup();
    d.add(make(Tool::Rect, Vec2(10, 10), Vec2(60, 60)));
    d.beginUndoGroup();
    d.applyCrop(RectD(5, 5, 200, 200));
    check(d.hasEdits(), "marks and a crop both count");

    d.beginUndoGroup();
    d.revert();
    check(d.count() == 0, "revert drops every mark");
    check(nearly(d.width(), 500) && nearly(d.height(), 400), "revert restores the frame");
    check(!d.hasEdits(), "a reverted document is unedited");

    d.undo();
    check(d.count() == 1 && nearly(d.width(), 200),
          "revert undoes as a single step, restoring marks and crop together");

    // A crop with no marks still counts as an edit worth reverting.
    Document e;
    e.reset(300, 300);
    e.applyCrop(RectD(0, 0, 150, 300));
    check(e.hasEdits(), "a crop alone is an edit");
    e.revert();
    check(!e.hasEdits(), "revert clears a crop-only edit");
}

}  // namespace

int main() {
    std::printf("skitch_core_tests");

    testGeometry();
    testAnnotationBounds();
    testHitTesting();
    testTransforms();
    testDocumentBasics();
    testDocumentHitAndOrder();
    testCrop();
    testUndo();
    testUndoDepth();
    testRevert();

    std::printf("\n%s — %d checks, %d failure%s\n", gFailures == 0 ? "PASS" : "FAIL",
                gChecks, gFailures, gFailures == 1 ? "" : "s");
    return gFailures == 0 ? 0 : 1;
}
