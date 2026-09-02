#import "capture/ScreenCapture.h"

#import <unistd.h>

@implementation SCDisplaySnapshot

- (void)setImage:(CGImageRef)image {
    if (_image == image) return;
    CGImageRelease(_image);
    _image = image ? CGImageRetain(image) : NULL;
}

- (void)dealloc {
    CGImageRelease(_image);
    _image = NULL;
}

@end

// ------------------------------------------------------------ permission ---

BOOL SCHasScreenRecordingPermission(void) {
    if (@available(macOS 10.15, *)) {
        return CGPreflightScreenCaptureAccess();
    }
    return YES;
}

BOOL SCRequestScreenRecordingPermission(void) {
    if (@available(macOS 10.15, *)) {
        if (CGPreflightScreenCaptureAccess()) return YES;
        return CGRequestScreenCaptureAccess();
    }
    return YES;
}

void SCShowPermissionAlert(void) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Skitch needs Screen Recording access";
    alert.informativeText =
        @"macOS blocks screen capture until the app is allowed in\n"
        @"System Settings › Privacy & Security › Screen Recording.\n\n"
        @"Enable Skitch there, then quit and reopen the app.";
    [alert addButtonWithTitle:@"Open System Settings"];
    [alert addButtonWithTitle:@"Later"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple."
                                          @"preference.security?Privacy_ScreenCapture"];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

// --------------------------------------------------------------- capture ---

CGImageRef SCCaptureDisplay(CGDirectDisplayID display) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return CGDisplayCreateImage(display);
#pragma clang diagnostic pop
}

NSArray<SCDisplaySnapshot *> *SCSnapshotAllDisplays(void) {
    NSMutableArray<SCDisplaySnapshot *> *out = [NSMutableArray array];

    for (NSScreen *screen in [NSScreen screens]) {
        NSNumber *num = screen.deviceDescription[@"NSScreenNumber"];
        if (!num) continue;
        const CGDirectDisplayID did = (CGDirectDisplayID)num.unsignedIntValue;

        CGImageRef img = SCCaptureDisplay(did);
        if (!img) continue;

        SCDisplaySnapshot *snap = [[SCDisplaySnapshot alloc] init];
        snap.displayID = did;
        snap.screen = screen;
        snap.image = img;
        CGImageRelease(img);

        const CGRect bounds = CGDisplayBounds(did);
        snap.scale = bounds.size.width > 0
                         ? (CGFloat)CGImageGetWidth(snap.image) / bounds.size.width
                         : screen.backingScaleFactor;
        [out addObject:snap];
    }
    return out;
}

CGImageRef SCCaptureWindow(CGWindowID windowID) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return CGWindowListCreateImage(
        CGRectNull, kCGWindowListOptionIncludingWindow, windowID,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution);
#pragma clang diagnostic pop
}

// ------------------------------------------------------- our own windows ---

const NSTimeInterval SCWindowHideSettleDelay = 0.12;

NSArray<NSWindow *> *SCHideOwnWindows(void) {
    NSMutableArray<NSWindow *> *hidden = [NSMutableArray array];

    // -orderedWindows is front-to-back, which is the order the caller hands
    // back to SCRestoreOwnWindows.
    for (NSWindow *w in [NSApp orderedWindows]) {
        if (!w.isVisible) continue;

        // The status bar item owns a window too, at a higher level; ordering
        // that out would take the menu bar icon away with it. Same reasoning
        // for anything else deliberately floated above the document windows.
        if (w.level != NSNormalWindowLevel) continue;

        [hidden addObject:w];
        [w orderOut:nil];
    }
    return hidden;
}

void SCRestoreOwnWindows(NSArray<NSWindow *> *windows) {
    // Back to front, so whichever window was in front ends up there again.
    for (NSWindow *w in [windows reverseObjectEnumerator]) {
        [w orderFront:nil];
    }
    // Hand focus back to the one that had it, so a cancelled capture leaves the
    // editor exactly as it was found. Sending this to nil is a no-op, which is
    // the right answer when nothing was hidden.
    [windows.firstObject makeKeyWindow];
}

NSArray<NSDictionary *> *SCOnScreenWindows(void) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];

    CFArrayRef list = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (!list) return out;

    const pid_t selfPID = getpid();

    for (NSDictionary *info in (__bridge NSArray *)list) {
        NSNumber *pid = info[(__bridge NSString *)kCGWindowOwnerPID];
        if (pid && pid.intValue == selfPID) continue;  // never target ourselves

        NSNumber *alpha = info[(__bridge NSString *)kCGWindowAlpha];
        if (alpha && alpha.doubleValue < 0.05) continue;

        NSNumber *wid = info[(__bridge NSString *)kCGWindowNumber];
        NSDictionary *boundsDict = info[(__bridge NSString *)kCGWindowBounds];
        if (!wid || !boundsDict) continue;

        CGRect bounds = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict,
                                                    &bounds)) {
            continue;
        }
        if (bounds.size.width < 24.0 || bounds.size.height < 24.0) continue;

        NSString *owner = info[(__bridge NSString *)kCGWindowOwnerName] ?: @"";
        [out addObject:@{
            @"windowID" : wid,
            @"bounds" : [NSValue valueWithRect:NSRectFromCGRect(bounds)],
            @"owner" : owner,
        }];
    }

    CFRelease(list);
    return out;
}
