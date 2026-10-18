// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#import "capture/ScreenCapture.h"

#import <ScreenCaptureKit/ScreenCaptureKit.h>
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
// ScreenCaptureKit only gained a still-image API (SCScreenshotManager) in
// macOS 14. Before that the CoreGraphics calls are the only synchronous way to
// grab a frame, so they stay as the fallback for 12 and 13. From macOS 15 on
// they are obsolete, and the system nags apps that still use them.

static CGDirectDisplayID DisplayIDForScreen(NSScreen *screen) {
    NSNumber *num = screen.deviceDescription[@"NSScreenNumber"];
    return num ? (CGDirectDisplayID)num.unsignedIntValue : kCGNullDirectDisplay;
}

static SCDisplaySnapshot *MakeSnapshot(NSScreen *screen, CGDirectDisplayID did,
                                       CGImageRef img) {
    SCDisplaySnapshot *snap = [[SCDisplaySnapshot alloc] init];
    snap.displayID = did;
    snap.screen = screen;
    snap.image = img;

    const CGRect bounds = CGDisplayBounds(did);
    snap.scale = bounds.size.width > 0
                     ? (CGFloat)CGImageGetWidth(img) / bounds.size.width
                     : screen.backingScaleFactor;
    return snap;
}

// ---- macOS 12–13 ----

static NSArray<SCDisplaySnapshot *> *LegacySnapshotAllDisplays(void) {
    NSMutableArray<SCDisplaySnapshot *> *out = [NSMutableArray array];

    for (NSScreen *screen in [NSScreen screens]) {
        const CGDirectDisplayID did = DisplayIDForScreen(screen);
        if (did == kCGNullDirectDisplay) continue;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CGImageRef img = CGDisplayCreateImage(did);
#pragma clang diagnostic pop
        if (!img) continue;

        [out addObject:MakeSnapshot(screen, did, img)];
        CGImageRelease(img);
    }
    return out;
}

static CGImageRef LegacyCaptureWindow(CGWindowID windowID) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return CGWindowListCreateImage(
        CGRectNull, kCGWindowListOptionIncludingWindow, windowID,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution);
#pragma clang diagnostic pop
}

// ---- macOS 14 and later ----

// Full native resolution of whatever the filter covers, without the cursor —
// matching what the CoreGraphics calls produced.
API_AVAILABLE(macos(14.0))
static SCStreamConfiguration *ConfigurationForFilter(SCContentFilter *filter) {
    SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
    const CGFloat scale = filter.pointPixelScale;
    config.width = (size_t)llround(filter.contentRect.size.width * scale);
    config.height = (size_t)llround(filter.contentRect.size.height * scale);
    config.captureResolution = SCCaptureResolutionBest;
    config.showsCursor = NO;
    config.ignoreShadowsSingleWindow = YES;
    return config;
}

API_AVAILABLE(macos(14.0))
static void ModernSnapshotAllDisplays(void (^completion)(NSArray<SCDisplaySnapshot *> *)) {
    [SCShareableContent getShareableContentWithCompletionHandler:^(
                            SCShareableContent *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!content) {
                completion(@[]);
                return;
            }

            // One slot per screen, filled as captures land, so the result keeps
            // NSScreen order however the completions interleave.
            NSArray<NSScreen *> *screens = [NSScreen screens];
            NSMutableArray *slots = [NSMutableArray arrayWithCapacity:screens.count];
            for (NSUInteger i = 0; i < screens.count; ++i) [slots addObject:[NSNull null]];

            dispatch_group_t group = dispatch_group_create();
            [screens enumerateObjectsUsingBlock:^(NSScreen *screen, NSUInteger i, BOOL *stop) {
                const CGDirectDisplayID did = DisplayIDForScreen(screen);
                SCDisplay *display = nil;
                for (SCDisplay *d in content.displays) {
                    if (d.displayID == did) display = d;
                }
                if (!display) return;

                SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display
                                                                  excludingWindows:@[]];
                dispatch_group_enter(group);
                [SCScreenshotManager
                    captureImageWithFilter:filter
                             configuration:ConfigurationForFilter(filter)
                         completionHandler:^(CGImageRef img, NSError *captureError) {
                             // The image is only lent for the duration of this block.
                             CGImageRef held = img ? CGImageRetain(img) : NULL;
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 if (held) {
                                     slots[i] = MakeSnapshot(screen, did, held);
                                     CGImageRelease(held);
                                 }
                                 dispatch_group_leave(group);
                             });
                         }];
            }];

            dispatch_group_notify(group, dispatch_get_main_queue(), ^{
                NSMutableArray<SCDisplaySnapshot *> *out = [NSMutableArray array];
                for (id slot in slots) {
                    if (slot != [NSNull null]) [out addObject:slot];
                }
                completion(out);
            });
        });
    }];
}

API_AVAILABLE(macos(14.0))
static void ModernCaptureWindow(CGWindowID windowID, void (^completion)(CGImageRef)) {
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES
                                               onScreenWindowsOnly:YES
                                                 completionHandler:^(
                                                     SCShareableContent *content,
                                                     NSError *error) {
        SCWindow *window = nil;
        for (SCWindow *w in content.windows) {
            if (w.windowID == windowID) window = w;
        }
        if (!window) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NULL); });
            return;
        }

        SCContentFilter *filter =
            [[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
        [SCScreenshotManager
            captureImageWithFilter:filter
                     configuration:ConfigurationForFilter(filter)
                 completionHandler:^(CGImageRef img, NSError *captureError) {
                     CGImageRef held = img ? CGImageRetain(img) : NULL;
                     dispatch_async(dispatch_get_main_queue(), ^{
                         completion(held);
                         CGImageRelease(held);
                     });
                 }];
    }];
}

// ---- entry points ----

void SCSnapshotAllDisplays(void (^completion)(NSArray<SCDisplaySnapshot *> *)) {
    if (@available(macOS 14.0, *)) {
        ModernSnapshotAllDisplays(completion);
    } else {
        completion(LegacySnapshotAllDisplays());
    }
}

void SCCaptureWindow(CGWindowID windowID, void (^completion)(CGImageRef)) {
    if (@available(macOS 14.0, *)) {
        ModernCaptureWindow(windowID, completion);
    } else {
        CGImageRef img = LegacyCaptureWindow(windowID);
        completion(img);
        CGImageRelease(img);
    }
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
