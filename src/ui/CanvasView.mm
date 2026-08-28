#import "ui/CanvasView.h"

#include <algorithm>
#include <vector>

#include "render/Renderer.h"

using sk::Annotation;
using sk::Grip;
using sk::RectD;
using sk::Tool;
using sk::Vec2;

namespace {

enum class DragMode { None, Creating, Moving, Resizing, Cropping };

sk::Color ToSk(NSColor *c) {
    NSColor *s = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!s) return sk::Color(1, 0, 0, 1);
    return sk::Color(s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent);
}

const CGFloat kHandleSize = 8.0;
const CGFloat kZoomSteps[] = {0.10, 0.15, 0.25, 0.33, 0.50, 0.67, 0.75, 1.0,
                              1.25, 1.50, 2.0,  3.0,  4.0,  6.0,  8.0};
const int kZoomStepCount = sizeof(kZoomSteps) / sizeof(kZoomSteps[0]);

}  // namespace

@interface SKCanvasView () <NSTextViewDelegate>
@end

@implementation SKCanvasView {
    DragMode _dragMode;
    Annotation _draft;
    BOOL _hasDraft;
    BOOL _didDrag;

    Vec2 _dragStartBase;
    Vec2 _dragLastBase;
    Annotation _dragOriginal;
    RectD _dragOriginalBounds;
    Grip _activeHandle;

    int _selectedID;
    int _editingID;

    RectD _cropRect;
    BOOL _hasCropRect;

    NSTextView *_textEditor;
    BOOL _suppressCommit;
}

@synthesize baseImage = _baseImage;

// ============================================================= lifecycle ===

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _dragMode = DragMode::None;
        _selectedID = 0;
        _editingID = 0;
        _activeHandle = Grip::None;
        _currentTool = Tool::Arrow;
        _strokeColor = [NSColor colorWithSRGBRed:0.93 green:0.16 blue:0.16 alpha:1.0];
        _lineWidth = 6.0;
        _fontSize = 28.0;
        _zoomLevel = 1.0;
        _captureScale = 1.0;
        _fillShapes = NO;
        self.wantsLayer = YES;
    }
    return self;
}

- (void)dealloc {
    CGImageRelease(_baseImage);
    _baseImage = NULL;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque { return NO; }
- (int)selectedAnnotationID { return _selectedID; }
- (BOOL)isEditingText { return _editingID != 0; }

- (void)setBaseImage:(CGImageRef)image {
    if (_baseImage == image) return;
    CGImageRelease(_baseImage);
    _baseImage = image ? CGImageRetain(image) : NULL;
    [self setNeedsDisplay:YES];
}

- (void)loadImage:(CGImageRef)image scale:(CGFloat)scale {
    [self commitPendingEdits];
    self.baseImage = image;
    self.captureScale = scale > 0 ? scale : 1.0;
    if (self.document && image) {
        self.document->reset(CGImageGetWidth(image), CGImageGetHeight(image));
    }
    _selectedID = 0;
    _editingID = 0;
    _hasDraft = NO;
    _hasCropRect = NO;
    [self refreshLayout];
    [self postStatus];
}

// ========================================================== coordinates ===

/// Points per base-image pixel.
- (CGFloat)pixelScale {
    const CGFloat cs = _captureScale > 0 ? _captureScale : 1.0;
    return _zoomLevel / cs;
}

- (NSPoint)viewPointForBase:(Vec2)p {
    if (!self.document) return NSZeroPoint;
    const RectD &crop = self.document->cropRect();
    const CGFloat k = [self pixelScale];
    return NSMakePoint((p.x - crop.x) * k, (p.y - crop.y) * k);
}

- (Vec2)basePointForView:(NSPoint)p {
    if (!self.document) return Vec2();
    const RectD &crop = self.document->cropRect();
    const CGFloat k = [self pixelScale];
    return Vec2(p.x / k + crop.x, p.y / k + crop.y);
}

- (NSRect)viewRectForBase:(RectD)r {
    const NSPoint a = [self viewPointForBase:Vec2(r.x, r.y)];
    const CGFloat k = [self pixelScale];
    return NSMakeRect(a.x, a.y, r.w * k, r.h * k);
}

- (void)refreshLayout {
    if (!self.document) return;
    const CGFloat k = [self pixelScale];
    NSSize size = NSMakeSize(std::max(1.0, self.document->width() * k),
                             std::max(1.0, self.document->height() * k));
    [self setFrameSize:size];
    [self setNeedsDisplay:YES];
}

// =============================================================== drawing ===

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)NSGraphicsContext.currentContext.CGContext;
    if (!self.document) return;

    const CGFloat k = [self pixelScale];

    // Checkerboard behind everything so transparent captures read correctly.
    [self drawCheckerboardInRect:dirty];

    CGContextSaveGState(ctx);
    CGContextScaleCTM(ctx, k, k);
    CGContextSetShouldAntialias(ctx, true);

    // Crisp pixels when zoomed in, smooth resampling when zoomed out.
    sk::drawBaseImage(ctx, *self.document, _baseImage,
                      k >= 1.0 ? kCGInterpolationNone : kCGInterpolationMedium);
    for (const Annotation &a : self.document->items()) {
        if (a.id == _editingID) continue;  // being edited inline
        sk::drawAnnotation(ctx, a, *self.document, _baseImage);
    }
    if (_hasDraft) {
        sk::drawPreview(ctx, _draft, *self.document, _baseImage);
    }

    CGContextRestoreGState(ctx);

    [self drawSelectionChrome];
    [self drawCropChrome];
}

- (void)drawCheckerboardInRect:(NSRect)dirty {
    const CGFloat cell = 8.0;
    [[NSColor colorWithWhite:0.86 alpha:1.0] setFill];
    NSRectFill(dirty);

    // Only tile the invalidated area — on a large capture the full-bounds loop
    // would be tens of thousands of fills per redraw.
    [[NSColor colorWithWhite:0.94 alpha:1.0] setFill];
    const CGFloat x0 = std::floor(NSMinX(dirty) / cell) * cell;
    const CGFloat y0 = std::floor(NSMinY(dirty) / cell) * cell;
    for (CGFloat y = y0; y < NSMaxY(dirty); y += cell) {
        for (CGFloat x = x0; x < NSMaxX(dirty); x += cell) {
            if ((static_cast<int>(x / cell) + static_cast<int>(y / cell)) % 2) continue;
            NSRectFill(NSIntersectionRect(NSMakeRect(x, y, cell, cell), dirty));
        }
    }
}

- (void)drawSelectionChrome {
    if (_selectedID == 0 || !self.document) return;
    const Annotation *a = self.document->find(_selectedID);
    if (!a) return;
    if (a->id == _editingID) {
        // Just a dashed frame around the live editor.
        NSRect r = NSInsetRect([self viewRectForBase:a->displayBounds()], -3, -3);
        NSBezierPath *p = [NSBezierPath bezierPathWithRect:r];
        CGFloat pattern[2] = {4, 3};
        [p setLineDash:pattern count:2 phase:0];
        [[NSColor colorWithSRGBRed:0.20 green:0.55 blue:1.0 alpha:0.9] setStroke];
        [p stroke];
        return;
    }

    NSColor *accent = [NSColor colorWithSRGBRed:0.20 green:0.55 blue:1.0 alpha:1.0];

    if (a->isLineLike()) {
        for (const Vec2 &p : {a->p0, a->p1}) {
            [self drawHandleAt:[self viewPointForBase:p] color:accent];
        }
        return;
    }

    NSRect box = [self viewRectForBase:a->displayBounds()];
    NSBezierPath *frame = [NSBezierPath bezierPathWithRect:NSInsetRect(box, -0.5, -0.5)];
    frame.lineWidth = 1.0;
    CGFloat pattern[2] = {4, 3};
    [frame setLineDash:pattern count:2 phase:0];
    [accent setStroke];
    [frame stroke];

    for (int i = 0; i < 8; ++i) {
        [self drawHandleAt:[self handlePointForRect:box handle:static_cast<Grip>(i)]
                     color:accent];
    }
}

- (void)drawHandleAt:(NSPoint)p color:(NSColor *)color {
    NSRect r = NSMakeRect(p.x - kHandleSize * 0.5, p.y - kHandleSize * 0.5, kHandleSize,
                          kHandleSize);
    [[NSColor whiteColor] setFill];
    NSRectFill(r);
    [color setStroke];
    NSBezierPath *p2 = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)];
    p2.lineWidth = 1.0;
    [p2 stroke];
}

- (void)drawCropChrome {
    if (!_hasCropRect) return;
    NSRect r = [self viewRectForBase:_cropRect];

    [[NSColor colorWithWhite:0.0 alpha:0.45] setFill];
    NSRectFillUsingOperation(NSMakeRect(0, 0, self.bounds.size.width, r.origin.y),
                             NSCompositingOperationSourceOver);
    NSRectFillUsingOperation(
        NSMakeRect(0, NSMaxY(r), self.bounds.size.width, self.bounds.size.height - NSMaxY(r)),
        NSCompositingOperationSourceOver);
    NSRectFillUsingOperation(NSMakeRect(0, r.origin.y, r.origin.x, r.size.height),
                             NSCompositingOperationSourceOver);
    NSRectFillUsingOperation(
        NSMakeRect(NSMaxX(r), r.origin.y, self.bounds.size.width - NSMaxX(r), r.size.height),
        NSCompositingOperationSourceOver);

    [[NSColor whiteColor] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)];
    border.lineWidth = 1.0;
    [border stroke];

    // Rule-of-thirds guides.
    [[NSColor colorWithWhite:1.0 alpha:0.35] setStroke];
    NSBezierPath *thirds = [NSBezierPath bezierPath];
    for (int i = 1; i < 3; ++i) {
        const CGFloat x = r.origin.x + r.size.width * i / 3.0;
        const CGFloat y = r.origin.y + r.size.height * i / 3.0;
        [thirds moveToPoint:NSMakePoint(x, r.origin.y)];
        [thirds lineToPoint:NSMakePoint(x, NSMaxY(r))];
        [thirds moveToPoint:NSMakePoint(r.origin.x, y)];
        [thirds lineToPoint:NSMakePoint(NSMaxX(r), y)];
    }
    [thirds stroke];
}

// =============================================================== handles ===

- (NSPoint)handlePointForRect:(NSRect)r handle:(Grip)h {
    const CGFloat x0 = NSMinX(r), x1 = NSMidX(r), x2 = NSMaxX(r);
    const CGFloat y0 = NSMinY(r), y1 = NSMidY(r), y2 = NSMaxY(r);
    switch (h) {
        case Grip::TopLeft: return NSMakePoint(x0, y0);
        case Grip::Top: return NSMakePoint(x1, y0);
        case Grip::TopRight: return NSMakePoint(x2, y0);
        case Grip::Right: return NSMakePoint(x2, y1);
        case Grip::BottomRight: return NSMakePoint(x2, y2);
        case Grip::Bottom: return NSMakePoint(x1, y2);
        case Grip::BottomLeft: return NSMakePoint(x0, y2);
        case Grip::Left: return NSMakePoint(x0, y1);
        default: return NSMakePoint(x1, y1);
    }
}

- (Grip)handleAtViewPoint:(NSPoint)p forAnnotation:(const Annotation *)a {
    const CGFloat grab = kHandleSize;

    if (a->isLineLike()) {
        const NSPoint s = [self viewPointForBase:a->p0];
        const NSPoint e = [self viewPointForBase:a->p1];
        if (fabs(p.x - s.x) <= grab && fabs(p.y - s.y) <= grab) return Grip::Start;
        if (fabs(p.x - e.x) <= grab && fabs(p.y - e.y) <= grab) return Grip::End;
        return Grip::None;
    }

    NSRect box = [self viewRectForBase:a->displayBounds()];
    for (int i = 0; i < 8; ++i) {
        const NSPoint hp = [self handlePointForRect:box handle:static_cast<Grip>(i)];
        if (fabs(p.x - hp.x) <= grab && fabs(p.y - hp.y) <= grab) {
            return static_cast<Grip>(i);
        }
    }
    return Grip::None;
}

- (RectD)rect:(RectD)r resizedWithHandle:(Grip)h toBase:(Vec2)p {
    double x0 = r.minX(), y0 = r.minY(), x1 = r.maxX(), y1 = r.maxY();
    switch (h) {
        case Grip::TopLeft: x0 = p.x; y0 = p.y; break;
        case Grip::Top: y0 = p.y; break;
        case Grip::TopRight: x1 = p.x; y0 = p.y; break;
        case Grip::Right: x1 = p.x; break;
        case Grip::BottomRight: x1 = p.x; y1 = p.y; break;
        case Grip::Bottom: y1 = p.y; break;
        case Grip::BottomLeft: x0 = p.x; y1 = p.y; break;
        case Grip::Left: x0 = p.x; break;
        default: break;
    }
    if (x1 < x0) std::swap(x0, x1);
    if (y1 < y0) std::swap(y0, y1);
    return RectD(x0, y0, std::max(2.0, x1 - x0), std::max(2.0, y1 - y0));
}

// ================================================================ events ===

- (void)resetCursorRects {
    NSCursor *cursor = [NSCursor arrowCursor];
    switch (_currentTool) {
        case Tool::Select: cursor = [NSCursor arrowCursor]; break;
        case Tool::Text: cursor = [NSCursor IBeamCursor]; break;
        case Tool::Crop: cursor = [NSCursor crosshairCursor]; break;
        default: cursor = [NSCursor crosshairCursor]; break;
    }
    [self addCursorRect:self.bounds cursor:cursor];
}

- (void)setCurrentTool:(sk::Tool)tool {
    if (_currentTool == tool) return;
    [self commitPendingEdits];
    _currentTool = tool;
    if (tool != Tool::Select) _selectedID = 0;
    if (tool != Tool::Crop) _hasCropRect = NO;
    [self.window invalidateCursorRectsForView:self];
    [self setNeedsDisplay:YES];
    [self postStatus];
}

- (Annotation)makeDraftAtBase:(Vec2)p {
    Annotation a;
    a.tool = _currentTool;
    a.stroke = ToSk(_strokeColor);
    a.fill = ToSk(_strokeColor).withAlpha(0.22);
    a.lineWidth = std::max(1.0, _lineWidth * (_captureScale > 0 ? _captureScale : 1.0));
    a.filled = _fillShapes;
    a.fontSize = _fontSize * (_captureScale > 0 ? _captureScale : 1.0);
    a.blockSize = std::max(4.0, _lineWidth * 2.0 * (_captureScale > 0 ? _captureScale : 1.0));
    a.p0 = p;
    a.p1 = p;
    if (a.isFreehand()) a.points.push_back(p);
    return a;
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    const NSPoint v = [self convertPoint:event.locationInWindow fromView:nil];
    const Vec2 p = [self basePointForView:v];
    _dragStartBase = p;
    _dragLastBase = p;
    _didDrag = NO;

    if (_editingID != 0) {
        [self commitPendingEdits];
        // A click that dismissed the editor should not also start a new mark.
        if (_currentTool == Tool::Text) return;
    }

    if (!self.document) return;

    switch (_currentTool) {
        case Tool::Select: {
            const Annotation *sel = self.document->find(_selectedID);
            if (sel) {
                const Grip h = [self handleAtViewPoint:v forAnnotation:sel];
                if (h != Grip::None) {
                    self.document->beginUndoGroup();
                    _dragOriginal = *sel;
                    _dragOriginalBounds = sel->coreBounds();
                    _activeHandle = h;
                    _dragMode = DragMode::Resizing;
                    return;
                }
            }
            const double tol = 6.0 / [self pixelScale];
            const int hit = self.document->hitTest(p, tol);
            _selectedID = hit;
            if (hit != 0) {
                if (event.clickCount >= 2) {
                    const Annotation *a = self.document->find(hit);
                    if (a && a->tool == Tool::Text) {
                        [self beginEditingText:hit];
                        return;
                    }
                }
                self.document->beginUndoGroup();
                _dragMode = DragMode::Moving;
            }
            [self setNeedsDisplay:YES];
            [self postStatus];
            return;
        }

        case Tool::Crop: {
            _hasCropRect = YES;
            _cropRect = RectD(p.x, p.y, 0, 0);
            _dragMode = DragMode::Cropping;
            [self setNeedsDisplay:YES];
            return;
        }

        case Tool::Text: {
            self.document->beginUndoGroup();
            Annotation a = [self makeDraftAtBase:p];
            a.text = "";
            const int id = self.document->add(a);
            _selectedID = id;
            [self beginEditingText:id];
            return;
        }

        default: {
            _draft = [self makeDraftAtBase:p];
            _hasDraft = YES;
            _dragMode = DragMode::Creating;
            [self setNeedsDisplay:YES];
            return;
        }
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.document) return;
    const NSPoint v = [self convertPoint:event.locationInWindow fromView:nil];
    Vec2 p = [self basePointForView:v];

    _didDrag = YES;
    const BOOL constrain = (event.modifierFlags & NSEventModifierFlagShift) != 0;

    switch (_dragMode) {
        case DragMode::Creating: {
            if (_draft.isFreehand()) {
                // Skip near-duplicate samples so the smoothing stays stable.
                if (_draft.points.empty() ||
                    (p - _draft.points.back()).length() > 1.0 / [self pixelScale]) {
                    _draft.points.push_back(p);
                }
            } else {
                if (constrain) p = [self constrainPoint:p from:_dragStartBase forTool:_draft.tool];
                _draft.p1 = p;
            }
            [self setNeedsDisplay:YES];
            break;
        }

        case DragMode::Moving: {
            Annotation *a = self.document->find(_selectedID);
            if (!a) break;
            Vec2 d = p - _dragLastBase;
            a->translate(d);
            _dragLastBase = p;
            [self setNeedsDisplay:YES];
            break;
        }

        case DragMode::Resizing: {
            Annotation *a = self.document->find(_selectedID);
            if (!a) break;
            if (_activeHandle == Grip::Start || _activeHandle == Grip::End) {
                Vec2 anchor = (_activeHandle == Grip::Start) ? _dragOriginal.p1
                                                               : _dragOriginal.p0;
                if (constrain) p = [self constrainPoint:p from:anchor forTool:a->tool];
                if (_activeHandle == Grip::Start) a->p0 = p; else a->p1 = p;
            } else {
                *a = _dragOriginal;
                const RectD to = [self rect:_dragOriginalBounds
                          resizedWithHandle:_activeHandle
                                     toBase:p];
                a->transformFromRectToRect(_dragOriginalBounds, to);
            }
            [self setNeedsDisplay:YES];
            break;
        }

        case DragMode::Cropping: {
            _cropRect = RectD::fromCorners(_dragStartBase, p);
            _cropRect = _cropRect.intersect(self.document->cropRect());
            [self setNeedsDisplay:YES];
            [self postStatus];
            break;
        }

        default:
            break;
    }
}

- (Vec2)constrainPoint:(Vec2)p from:(Vec2)origin forTool:(Tool)tool {
    const double dx = p.x - origin.x;
    const double dy = p.y - origin.y;
    if (tool == Tool::Rect || tool == Tool::Ellipse || tool == Tool::Pixelate) {
        const double d = std::max(std::fabs(dx), std::fabs(dy));
        return Vec2(origin.x + (dx < 0 ? -d : d), origin.y + (dy < 0 ? -d : d));
    }
    // Snap lines/arrows to 15-degree increments.
    const double angle = std::atan2(dy, dx);
    const double step = M_PI / 12.0;
    const double snapped = std::round(angle / step) * step;
    const double len = std::sqrt(dx * dx + dy * dy);
    return Vec2(origin.x + std::cos(snapped) * len, origin.y + std::sin(snapped) * len);
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.document) return;

    switch (_dragMode) {
        case DragMode::Creating: {
            _hasDraft = NO;
            BOOL meaningful = YES;
            if (_draft.isFreehand()) {
                meaningful = _draft.points.size() >= 1;
            } else {
                const RectD b = RectD::fromCorners(_draft.p0, _draft.p1);
                const double minSize = 3.0 / [self pixelScale];
                meaningful = (b.w > minSize || b.h > minSize);
            }
            if (meaningful) {
                self.document->beginUndoGroup();
                _selectedID = self.document->add(_draft);
                [self notifyEdited];
            }
            [self setNeedsDisplay:YES];
            break;
        }

        case DragMode::Moving:
        case DragMode::Resizing:
            if (_didDrag) {
                [self notifyEdited];
            } else {
                // A plain click on an existing mark must not add an undo step.
                self.document->abortUndoGroup();
            }
            break;

        case DragMode::Cropping: {
            const RectD r = _cropRect;
            _hasCropRect = NO;
            _dragMode = DragMode::None;
            if (r.w > 8.0 && r.h > 8.0) {
                self.document->beginUndoGroup();
                const RectD &crop = self.document->cropRect();
                self.document->applyCrop(RectD(r.x - crop.x, r.y - crop.y, r.w, r.h));
                [self refreshLayout];
                [self notifyEdited];
                [self.delegate canvasViewDidResizeDocument:self];
            }
            [self.delegate canvasViewDidFinishOneShotTool:self];
            [self setNeedsDisplay:YES];
            [self postStatus];
            return;
        }

        default:
            break;
    }

    _dragMode = DragMode::None;
    _activeHandle = Grip::None;
    [self postStatus];
}

- (void)mouseMoved:(NSEvent *)event { [self postStatus]; }

- (void)magnifyWithEvent:(NSEvent *)event {
    self.zoomLevel = static_cast<CGFloat>(
        sk::clampd(_zoomLevel * (1.0 + event.magnification), 0.05, 16.0));
    [self refreshLayout];
    [self postStatus];
}

- (void)scrollWheel:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        const CGFloat factor = 1.0 + event.scrollingDeltaY * 0.01;
        self.zoomLevel =
            static_cast<CGFloat>(sk::clampd(_zoomLevel * factor, 0.05, 16.0));
        [self refreshLayout];
        [self postStatus];
        return;
    }
    [super scrollWheel:event];
}

- (void)keyDown:(NSEvent *)event {
    if (!self.document) {
        [super keyDown:event];
        return;
    }

    switch (event.keyCode) {
        case 51:   // Delete
        case 117:  // Forward delete
            [self deleteSelection];
            return;
        case 53:  // Escape
            [self commitPendingEdits];
            _selectedID = 0;
            _hasCropRect = NO;
            [self setNeedsDisplay:YES];
            return;
        case 123:
        case 124:
        case 125:
        case 126: {
            if (_selectedID == 0) break;
            Annotation *a = self.document->find(_selectedID);
            if (!a) break;
            const double step = (event.modifierFlags & NSEventModifierFlagShift) ? 10.0 : 1.0;
            Vec2 d;
            if (event.keyCode == 123) d = Vec2(-step, 0);
            if (event.keyCode == 124) d = Vec2(step, 0);
            if (event.keyCode == 125) d = Vec2(0, step);
            if (event.keyCode == 126) d = Vec2(0, -step);
            self.document->beginUndoGroup();
            a->translate(d);
            [self notifyEdited];
            [self setNeedsDisplay:YES];
            return;
        }
        default:
            break;
    }
    [super keyDown:event];
}

// ========================================================== text editing ===

- (void)beginEditingText:(int)annotationID {
    if (!self.document) return;
    Annotation *a = self.document->find(annotationID);
    if (!a || a->tool != Tool::Text) return;

    _editingID = annotationID;
    _selectedID = annotationID;

    const CGFloat k = [self pixelScale];
    const CGFloat displayFont = std::max(6.0, a->fontSize * k);

    if (!_textEditor) {
        _textEditor = [[NSTextView alloc] initWithFrame:NSZeroRect];
        _textEditor.delegate = self;
        _textEditor.drawsBackground = NO;
        _textEditor.richText = NO;
        _textEditor.usesFontPanel = NO;
        _textEditor.allowsUndo = YES;
        _textEditor.textContainerInset = NSZeroSize;
        _textEditor.textContainer.lineFragmentPadding = 0.0;
        _textEditor.horizontallyResizable = YES;
        _textEditor.verticallyResizable = YES;
        _textEditor.autoresizingMask = NSViewNotSizable;
    }

    NSFont *font = [NSFont fontWithName:@(sk::textFontName()) size:displayFont]
                       ?: [NSFont boldSystemFontOfSize:displayFont];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.minimumLineHeight = a->fontSize * 1.28 * k;
    ps.maximumLineHeight = a->fontSize * 1.28 * k;

    _textEditor.font = font;
    _textEditor.defaultParagraphStyle = ps;
    _textEditor.typingAttributes = @{
        NSFontAttributeName : font,
        NSParagraphStyleAttributeName : ps,
        NSForegroundColorAttributeName : _strokeColor,
    };
    _textEditor.textColor = _strokeColor;
    _textEditor.insertionPointColor = _strokeColor;
    _textEditor.string = [NSString stringWithUTF8String:a->text.c_str()] ?: @"";

    [self addSubview:_textEditor];
    [self layoutTextEditorForAnnotation:a];
    [self.window makeFirstResponder:_textEditor];
    [_textEditor setSelectedRange:NSMakeRange(_textEditor.string.length, 0)];
    [self setNeedsDisplay:YES];
}

- (void)layoutTextEditorForAnnotation:(const Annotation *)a {
    if (!_textEditor) return;
    const CGFloat k = [self pixelScale];
    const NSPoint origin = [self viewPointForBase:a->p0];

    NSSize contentSize = NSMakeSize(240, 40);
    NSLayoutManager *lm = _textEditor.layoutManager;
    NSTextContainer *tc = _textEditor.textContainer;
    if (lm && tc) {
        tc.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        tc.widthTracksTextView = NO;
        [lm ensureLayoutForTextContainer:tc];
        contentSize = [lm usedRectForTextContainer:tc].size;
    }
    const CGFloat lineH = a->fontSize * 1.28 * k;
    contentSize.width = std::max<CGFloat>(contentSize.width + lineH * 0.7, lineH);
    contentSize.height = std::max<CGFloat>(contentSize.height, lineH);

    _textEditor.frame = NSMakeRect(origin.x, origin.y, contentSize.width, contentSize.height);
}

- (void)textDidChange:(NSNotification *)notification {
    if (!self.document || _editingID == 0) return;
    Annotation *a = self.document->find(_editingID);
    if (!a) return;
    a->text = _textEditor.string.UTF8String ?: "";
    a->measuredWidth = a->measuredHeight = 0.0;
    [self layoutTextEditorForAnnotation:a];
    [self setNeedsDisplay:YES];
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (selector == @selector(cancelOperation:)) {
        [self commitPendingEdits];
        return YES;
    }
    return NO;
}

- (void)commitPendingEdits {
    if (_editingID == 0 || _suppressCommit) return;
    _suppressCommit = YES;

    const int id = _editingID;
    _editingID = 0;

    NSString *value = _textEditor.string ?: @"";
    [_textEditor removeFromSuperview];

    if (self.document) {
        Annotation *a = self.document->find(id);
        if (a) {
            if (value.length == 0) {
                self.document->remove(id);
                if (_selectedID == id) _selectedID = 0;
            } else {
                a->text = value.UTF8String ?: "";
                a->measuredWidth = a->measuredHeight = 0.0;
                [self notifyEdited];
            }
        }
    }

    if (self.window.firstResponder == _textEditor || !self.window.firstResponder) {
        [self.window makeFirstResponder:self];
    }
    _suppressCommit = NO;
    [self setNeedsDisplay:YES];
}

// =============================================================== actions ===

- (void)deleteSelection {
    if (!self.document || _selectedID == 0) return;
    [self commitPendingEdits];
    self.document->beginUndoGroup();
    if (self.document->remove(_selectedID)) {
        _selectedID = 0;
        [self notifyEdited];
        [self setNeedsDisplay:YES];
    } else {
        self.document->abortUndoGroup();
    }
}

- (void)deleteAllAnnotations {
    if (!self.document || self.document->count() == 0) return;
    [self commitPendingEdits];
    self.document->beginUndoGroup();
    self.document->clear();
    _selectedID = 0;
    [self notifyEdited];
    [self setNeedsDisplay:YES];
}

- (void)selectAll {
    if (!self.document || self.document->items().empty()) return;
    _selectedID = self.document->items().back().id;
    self.currentTool = Tool::Select;
    [self setNeedsDisplay:YES];
}

- (void)deselect {
    _selectedID = 0;
    [self setNeedsDisplay:YES];
}

- (void)bringSelectionForward {
    if (!self.document || _selectedID == 0) return;
    self.document->beginUndoGroup();
    if (self.document->raise(_selectedID)) {
        [self notifyEdited];
        [self setNeedsDisplay:YES];
    } else {
        self.document->abortUndoGroup();
    }
}

- (void)sendSelectionBackward {
    if (!self.document || _selectedID == 0) return;
    self.document->beginUndoGroup();
    if (self.document->lower(_selectedID)) {
        [self notifyEdited];
        [self setNeedsDisplay:YES];
    } else {
        self.document->abortUndoGroup();
    }
}

- (void)revertToOriginal {
    if (!self.document) return;
    [self commitPendingEdits];
    if (!self.document->hasEdits()) return;
    self.document->beginUndoGroup();
    self.document->revert();
    _selectedID = 0;
    _hasCropRect = NO;
    [self refreshLayout];
    [self notifyEdited];
    [self.delegate canvasViewDidResizeDocument:self];
    [self postStatus];
}

- (void)resetCrop {
    if (!self.document) return;
    [self commitPendingEdits];
    self.document->beginUndoGroup();
    self.document->resetCrop();
    [self refreshLayout];
    [self notifyEdited];
    [self.delegate canvasViewDidResizeDocument:self];
}

// ================================================================== zoom ===

- (void)zoomIn {
    for (int i = 0; i < kZoomStepCount; ++i) {
        if (kZoomSteps[i] > _zoomLevel + 1e-4) {
            self.zoomLevel = kZoomSteps[i];
            break;
        }
    }
    [self refreshLayout];
    [self postStatus];
}

- (void)zoomOut {
    for (int i = kZoomStepCount - 1; i >= 0; --i) {
        if (kZoomSteps[i] < _zoomLevel - 1e-4) {
            self.zoomLevel = kZoomSteps[i];
            break;
        }
    }
    [self refreshLayout];
    [self postStatus];
}

- (void)zoomToActualSize {
    self.zoomLevel = 1.0;
    [self refreshLayout];
    [self postStatus];
}

- (void)zoomToFitInSize:(NSSize)available {
    if (!self.document || self.document->width() <= 0) return;
    const CGFloat cs = _captureScale > 0 ? _captureScale : 1.0;
    const CGFloat wPts = self.document->width() / cs;
    const CGFloat hPts = self.document->height() / cs;
    if (wPts <= 0 || hPts <= 0) return;
    const CGFloat fit = std::min<CGFloat>(available.width / wPts, available.height / hPts);
    self.zoomLevel = static_cast<CGFloat>(sk::clampd(std::min<CGFloat>(fit, 1.0), 0.05, 16.0));
    [self refreshLayout];
    [self postStatus];
}

// ================================================================ output ===

- (CGImageRef)createFlattenedImage {
    [self commitPendingEdits];
    if (!self.document || !_baseImage) return NULL;
    return sk::renderToImage(*self.document, _baseImage);
}

// ================================================================= misc ====

- (void)notifyEdited {
    [self.delegate canvasViewDidEditDocument:self];
}

- (void)postStatus {
    if (!self.document) return;
    NSString *s =
        [NSString stringWithFormat:@"%.0f × %.0f px   ·   %.0f%%   ·   %s   ·   %lu marks",
                                   self.document->width(), self.document->height(),
                                   _zoomLevel * 100.0, sk::toolName(_currentTool),
                                   (unsigned long)self.document->count()];
    [self.delegate canvasView:self didUpdateStatus:s];
}

@end
