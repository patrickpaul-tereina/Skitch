// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#import "capture/OverlayWindow.h"

#import "capture/ScreenCapture.h"

// ---------------------------------------------------------------- window ---

@interface SCOverlayWindow : NSWindow
@end

@implementation SCOverlayWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

// ------------------------------------------------------------------ view ---

@class SCOverlayView;

@protocol SCOverlayViewDelegate <NSObject>
- (void)overlayView:(SCOverlayView *)view didSelectRegion:(NSRect)localRect;
- (void)overlayView:(SCOverlayView *)view didSelectWindowID:(CGWindowID)wid;
- (void)overlayViewDidCancel:(SCOverlayView *)view;
- (void)overlayViewDidRequestModeToggle:(SCOverlayView *)view;
- (SCCaptureMode)overlayViewCaptureMode:(SCOverlayView *)view;
@end

@interface SCOverlayView : NSView
@property(nonatomic, weak) id<SCOverlayViewDelegate> delegate;
@property(nonatomic, strong) SCDisplaySnapshot *snapshot;
@property(nonatomic, strong) NSArray<NSDictionary *> *windowList;
- (void)refreshHover;
@end

@implementation SCOverlayView {
    BOOL _dragging;
    NSPoint _anchor;
    NSPoint _current;
    NSPoint _mouse;
    BOOL _hasMouse;
    CGWindowID _hoverWindowID;
    NSRect _hoverRect;
    NSTrackingArea *_tracking;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor crosshairCursor]];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseMoved | NSTrackingActiveAlways |
                     NSTrackingMouseEnteredAndExited | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_tracking];
}

// ---- geometry ------------------------------------------------------------

- (NSRect)selectionRect {
    return NSMakeRect(MIN(_anchor.x, _current.x), MIN(_anchor.y, _current.y),
                      fabs(_current.x - _anchor.x), fabs(_current.y - _anchor.y));
}

/// Local (flipped, top-left origin) point -> CoreGraphics global point.
- (CGPoint)globalPointForLocal:(NSPoint)p {
    const CGRect db = CGDisplayBounds(self.snapshot.displayID);
    return CGPointMake(db.origin.x + p.x, db.origin.y + p.y);
}

- (NSRect)localRectForGlobalRect:(CGRect)r {
    const CGRect db = CGDisplayBounds(self.snapshot.displayID);
    return NSMakeRect(r.origin.x - db.origin.x, r.origin.y - db.origin.y, r.size.width,
                      r.size.height);
}

- (void)refreshHover {
    _hoverWindowID = kCGNullWindowID;
    _hoverRect = NSZeroRect;
    if (!_hasMouse) return;
    if ([self.delegate overlayViewCaptureMode:self] != SCCaptureModeWindow) return;

    const CGPoint g = [self globalPointForLocal:_mouse];
    for (NSDictionary *info in self.windowList) {
        const NSRect b = [info[@"bounds"] rectValue];
        if (CGRectContainsPoint(NSRectToCGRect(b), g)) {
            _hoverWindowID = (CGWindowID)[info[@"windowID"] unsignedIntValue];
            _hoverRect = [self localRectForGlobalRect:NSRectToCGRect(b)];
            break;  // list is already front-to-back
        }
    }
}

// ---- drawing -------------------------------------------------------------

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)NSGraphicsContext.currentContext.CGContext;
    const NSRect b = self.bounds;

    if (self.snapshot.image) {
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 0, b.size.height);
        CGContextScaleCTM(ctx, 1, -1);
        CGContextDrawImage(ctx, CGRectMake(0, 0, b.size.width, b.size.height),
                           self.snapshot.image);
        CGContextRestoreGState(ctx);
    } else {
        [[NSColor blackColor] setFill];
        NSRectFill(b);
    }

    [[NSColor colorWithWhite:0.0 alpha:0.42] setFill];
    NSRectFillUsingOperation(b, NSCompositingOperationSourceOver);

    const SCCaptureMode mode = [self.delegate overlayViewCaptureMode:self];
    NSRect focus = NSZeroRect;
    if (mode == SCCaptureModeWindow) {
        focus = _hoverRect;
    } else if (_dragging || !NSIsEmptyRect([self selectionRect])) {
        focus = [self selectionRect];
    }

    if (!NSIsEmptyRect(focus)) {
        // Punch the focused area back to full brightness.
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, NSRectToCGRect(focus));
        if (self.snapshot.image) {
            CGContextTranslateCTM(ctx, 0, b.size.height);
            CGContextScaleCTM(ctx, 1, -1);
            CGContextDrawImage(ctx, CGRectMake(0, 0, b.size.width, b.size.height),
                               self.snapshot.image);
        }
        CGContextRestoreGState(ctx);

        if (mode == SCCaptureModeWindow) {
            [[NSColor colorWithSRGBRed:0.25 green:0.55 blue:1.0 alpha:0.22] setFill];
            NSRectFillUsingOperation(focus, NSCompositingOperationSourceOver);
            [[NSColor colorWithSRGBRed:0.35 green:0.65 blue:1.0 alpha:0.95] setStroke];
        } else {
            [[NSColor whiteColor] setStroke];
        }
        NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(focus, 0.5, 0.5)];
        border.lineWidth = 1.5;
        [border stroke];

        [self drawBadgeForRect:focus];
    } else if (_hasMouse && mode == SCCaptureModeRegion) {
        [[NSColor colorWithWhite:1.0 alpha:0.55] setStroke];
        NSBezierPath *guides = [NSBezierPath bezierPath];
        guides.lineWidth = 1.0;
        [guides moveToPoint:NSMakePoint(0, floor(_mouse.y) + 0.5)];
        [guides lineToPoint:NSMakePoint(b.size.width, floor(_mouse.y) + 0.5)];
        [guides moveToPoint:NSMakePoint(floor(_mouse.x) + 0.5, 0)];
        [guides lineToPoint:NSMakePoint(floor(_mouse.x) + 0.5, b.size.height)];
        [guides stroke];
    }

    [self drawHintBanner];
}

- (void)drawBadgeForRect:(NSRect)r {
    const CGFloat s = self.snapshot.scale > 0 ? self.snapshot.scale : 1.0;
    NSString *label =
        [NSString stringWithFormat:@"%.0f × %.0f", round(r.size.width * s),
                                   round(r.size.height * s)];

    NSDictionary *attrs = @{
        NSFontAttributeName : [NSFont monospacedDigitSystemFontOfSize:12
                                                               weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : [NSColor whiteColor],
    };
    const NSSize ts = [label sizeWithAttributes:attrs];
    NSRect box = NSMakeRect(r.origin.x, r.origin.y - ts.height - 10, ts.width + 12,
                            ts.height + 6);
    if (box.origin.y < 4) box.origin.y = NSMaxY(r) + 6;
    box.origin.x = MAX(4, MIN(box.origin.x, NSMaxX(self.bounds) - box.size.width - 4));

    [[NSColor colorWithWhite:0.0 alpha:0.75] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:box xRadius:4 yRadius:4] fill];
    [label drawAtPoint:NSMakePoint(box.origin.x + 6, box.origin.y + 3) withAttributes:attrs];
}

- (void)drawHintBanner {
    if (self.snapshot.screen != [NSScreen mainScreen]) return;

    const SCCaptureMode mode = [self.delegate overlayViewCaptureMode:self];
    NSString *hint = (mode == SCCaptureModeWindow)
                         ? @"Click a window to capture   ·   Space: region mode   ·   Esc: cancel"
                         : @"Drag to select   ·   Space: window mode   ·   Return: whole screen   ·   Esc: cancel";

    NSDictionary *attrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : [NSColor whiteColor],
    };
    const NSSize ts = [hint sizeWithAttributes:attrs];
    NSRect box = NSMakeRect((self.bounds.size.width - ts.width - 28) * 0.5, 28,
                            ts.width + 28, ts.height + 16);

    [[NSColor colorWithWhite:0.08 alpha:0.85] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:box xRadius:9 yRadius:9] fill];
    [hint drawAtPoint:NSMakePoint(box.origin.x + 14, box.origin.y + 8) withAttributes:attrs];
}

// ---- events --------------------------------------------------------------

- (void)mouseEntered:(NSEvent *)event { _hasMouse = YES; }

- (void)mouseExited:(NSEvent *)event {
    _hasMouse = NO;
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event {
    _hasMouse = YES;
    _mouse = [self convertPoint:event.locationInWindow fromView:nil];
    [self refreshHover];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    _mouse = [self convertPoint:event.locationInWindow fromView:nil];
    if ([self.delegate overlayViewCaptureMode:self] == SCCaptureModeWindow) return;
    _dragging = YES;
    _anchor = _mouse;
    _current = _mouse;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    _mouse = [self convertPoint:event.locationInWindow fromView:nil];
    if (!_dragging) return;
    _current = _mouse;
    if (event.modifierFlags & NSEventModifierFlagShift) {  // square selection
        const CGFloat d = MAX(fabs(_current.x - _anchor.x), fabs(_current.y - _anchor.y));
        _current.x = _anchor.x + (_current.x < _anchor.x ? -d : d);
        _current.y = _anchor.y + (_current.y < _anchor.y ? -d : d);
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    _mouse = [self convertPoint:event.locationInWindow fromView:nil];

    if ([self.delegate overlayViewCaptureMode:self] == SCCaptureModeWindow) {
        [self refreshHover];
        if (_hoverWindowID != kCGNullWindowID) {
            [self.delegate overlayView:self didSelectWindowID:_hoverWindowID];
        } else {
            [self.delegate overlayViewDidCancel:self];
        }
        return;
    }

    if (!_dragging) return;
    _dragging = NO;
    const NSRect r = [self selectionRect];
    if (r.size.width < 3.0 || r.size.height < 3.0) {
        _anchor = _current = NSZeroPoint;
        [self setNeedsDisplay:YES];
        return;
    }
    [self.delegate overlayView:self didSelectRegion:r];
}

- (void)keyDown:(NSEvent *)event {
    switch (event.keyCode) {
        case 53:  // Escape
            [self.delegate overlayViewDidCancel:self];
            return;
        case 49:  // Space
            [self.delegate overlayViewDidRequestModeToggle:self];
            return;
        case 36:  // Return
        case 76:  // Keypad Enter
            [self.delegate overlayView:self didSelectRegion:self.bounds];
            return;
        default:
            break;
    }
    [super keyDown:event];
}

@end

// ------------------------------------------------------------ controller ---

@interface SCOverlayController () <SCOverlayViewDelegate>
@property(nonatomic, strong) NSArray<SCDisplaySnapshot *> *snapshots;
@property(nonatomic, strong) NSMutableArray<NSWindow *> *windows;
@property(nonatomic, copy) SCCaptureCompletion completion;
@property(nonatomic) SCCaptureMode mode;
@property(nonatomic, strong) NSArray<NSDictionary *> *windowList;
@property(nonatomic, strong) NSArray<NSWindow *> *hiddenWindows;
@property(nonatomic) BOOL finished;
@end

static SCOverlayController *gActiveController = nil;

@implementation SCOverlayController

+ (BOOL)isCapturing { return gActiveController != nil; }

+ (void)beginCaptureWithMode:(SCCaptureMode)mode
                       delay:(NSTimeInterval)delay
                  completion:(SCCaptureCompletion)completion {
    if (gActiveController) return;

    if (!SCRequestScreenRecordingPermission()) {
        SCShowPermissionAlert();
        completion(NULL, 1.0);
        return;
    }

    if (delay > 0.0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [self beginCaptureWithMode:mode delay:0 completion:completion];
                       });
        return;
    }

    SCOverlayController *c = [[SCOverlayController alloc] init];
    c.completion = completion;
    c.mode = mode;
    gActiveController = c;
    [c start];
}

- (void)start {
    // Get out of our own way first. A capture started from the palette's
    // Capture button — or from a menu while an editor is frontmost — is aimed
    // at whatever that window is covering, and the snapshot below would
    // otherwise freeze Skitch's own interface into the shot. finishWithImage:
    // puts the windows back, including when the capture is cancelled.
    self.hiddenWindows = SCHideOwnWindows();

    if (self.hiddenWindows.count == 0) {
        [self snapshotAndPresent];
        return;
    }

    // -orderOut: returns before the window server has actually composited the
    // windows away, so snapshotting on this turn of the loop would still catch
    // them. Nothing reports when that has happened; a short wait is the
    // available answer, and it doubles as the visual cue that Skitch stepped
    // aside.
    __weak SCOverlayController *weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SCWindowHideSettleDelay * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [weakSelf snapshotAndPresent];
        });
}

- (void)snapshotAndPresent {
    self.snapshots = SCSnapshotAllDisplays();
    if (self.snapshots.count == 0) {
        SCShowPermissionAlert();
        [self finishWithImage:NULL scale:1.0];
        return;
    }

    if (self.mode == SCCaptureModeFullScreen) {
        SCDisplaySnapshot *snap = [self snapshotForMouse];
        CGImageRef img = snap.image ? CGImageRetain(snap.image) : NULL;
        [self finishWithImage:img scale:snap.scale];
        return;
    }

    self.windowList = SCOnScreenWindows();
    self.windows = [NSMutableArray array];

    for (SCDisplaySnapshot *snap in self.snapshots) {
        SCOverlayWindow *w =
            [[SCOverlayWindow alloc] initWithContentRect:snap.screen.frame
                                               styleMask:NSWindowStyleMaskBorderless
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
        w.opaque = NO;
        w.backgroundColor = [NSColor clearColor];
        w.level = NSScreenSaverWindowLevel;
        w.ignoresMouseEvents = NO;
        w.acceptsMouseMovedEvents = YES;
        w.releasedWhenClosed = NO;
        w.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorFullScreenAuxiliary |
                               NSWindowCollectionBehaviorStationary;

        SCOverlayView *v = [[SCOverlayView alloc] initWithFrame:NSMakeRect(0, 0,
                                                                           snap.screen.frame.size.width,
                                                                           snap.screen.frame.size.height)];
        v.delegate = self;
        v.snapshot = snap;
        v.windowList = self.windowList;
        v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        w.contentView = v;

        [w makeKeyAndOrderFront:nil];
        [self.windows addObject:w];
    }

    [NSApp activateIgnoringOtherApps:YES];
    NSWindow *keyWindow = self.windows.firstObject;
    for (NSWindow *w in self.windows) {
        if (w.screen == [NSScreen mainScreen]) keyWindow = w;
    }
    [keyWindow makeKeyAndOrderFront:nil];
    [keyWindow makeFirstResponder:keyWindow.contentView];
}

- (SCDisplaySnapshot *)snapshotForMouse {
    const NSPoint mouse = [NSEvent mouseLocation];
    for (SCDisplaySnapshot *snap in self.snapshots) {
        if (NSPointInRect(mouse, snap.screen.frame)) return snap;
    }
    return self.snapshots.firstObject;
}

- (void)tearDownWindows {
    for (NSWindow *w in self.windows) [w orderOut:nil];
    [self.windows removeAllObjects];
}

- (void)finishWithImage:(CGImageRef)image scale:(CGFloat)scale {
    if (self.finished) {
        CGImageRelease(image);
        return;
    }
    self.finished = YES;
    [self tearDownWindows];

    // Back before the completion runs, so a new editor window opens in front of
    // the ones that were already there rather than behind them.
    SCRestoreOwnWindows(self.hiddenWindows);
    self.hiddenWindows = nil;

    SCCaptureCompletion completion = self.completion;
    self.completion = nil;
    gActiveController = nil;

    // Let the overlay actually disappear before the editor window shows up.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(image, scale);
        else CGImageRelease(image);
    });
}

// ---- SCOverlayViewDelegate ----------------------------------------------

- (SCCaptureMode)overlayViewCaptureMode:(SCOverlayView *)view { return self.mode; }

- (void)overlayViewDidRequestModeToggle:(SCOverlayView *)view {
    self.mode = (self.mode == SCCaptureModeWindow) ? SCCaptureModeRegion
                                                   : SCCaptureModeWindow;
    for (NSWindow *w in self.windows) {
        SCOverlayView *v = (SCOverlayView *)w.contentView;
        [v refreshHover];
        [v setNeedsDisplay:YES];
    }
}

- (void)overlayViewDidCancel:(SCOverlayView *)view { [self finishWithImage:NULL scale:1.0]; }

- (void)overlayView:(SCOverlayView *)view didSelectRegion:(NSRect)localRect {
    SCDisplaySnapshot *snap = view.snapshot;
    if (!snap.image) {
        [self finishWithImage:NULL scale:1.0];
        return;
    }

    const CGFloat s = snap.scale > 0 ? snap.scale : 1.0;
    CGRect px = CGRectMake(round(localRect.origin.x * s), round(localRect.origin.y * s),
                           round(localRect.size.width * s), round(localRect.size.height * s));
    px = CGRectIntersection(
        px, CGRectMake(0, 0, CGImageGetWidth(snap.image), CGImageGetHeight(snap.image)));
    if (CGRectIsNull(px) || px.size.width < 1 || px.size.height < 1) {
        [self finishWithImage:NULL scale:1.0];
        return;
    }

    CGImageRef cropped = CGImageCreateWithImageInRect(snap.image, px);
    [self finishWithImage:cropped scale:s];
}

- (void)overlayView:(SCOverlayView *)view didSelectWindowID:(CGWindowID)wid {
    // Drop the overlay first so nothing of ours can bleed into the shot.
    [self tearDownWindows];
    const CGFloat fallbackScale = view.snapshot.scale > 0 ? view.snapshot.scale : 1.0;

    __weak SCOverlayController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       SCOverlayController *self_ = weakSelf;
                       if (!self_) return;
                       CGImageRef img = SCCaptureWindow(wid);
                       [self_ finishWithImage:img scale:fallbackScale];
                   });
}

@end
