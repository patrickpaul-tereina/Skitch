// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
// Thin wrapper over the window/display capture APIs — ScreenCaptureKit on
// macOS 14 and later, the older CoreGraphics calls before that — plus the
// Screen Recording permission dance macOS requires before any of them return
// real pixels.
#pragma once

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// A frozen copy of one display, taken before the selection overlay appears so
/// the overlay itself never ends up in the shot.
@interface SCDisplaySnapshot : NSObject
@property(nonatomic) CGDirectDisplayID displayID;
@property(nonatomic, strong) NSScreen *screen;
@property(nonatomic) CGImageRef image;  // retained; released on dealloc
/// Pixels per point for this display.
@property(nonatomic) CGFloat scale;
@end

/// YES once the user has granted Screen Recording to this app.
BOOL SCHasScreenRecordingPermission(void);

/// Triggers the system prompt (only ever shown once per app identity) and
/// returns whether access is now granted.
BOOL SCRequestScreenRecordingPermission(void);

/// Puts up an alert explaining how to grant the permission manually.
void SCShowPermissionAlert(void);

/// One snapshot per attached display, in NSScreen order. Displays that could
/// not be captured are left out, so an empty array usually means the Screen
/// Recording permission is missing. `completion` runs on the main queue.
void SCSnapshotAllDisplays(void (^completion)(NSArray<SCDisplaySnapshot *> *snapshots));

/// Full-resolution grab of one window, excluding its shadow. `completion` runs
/// on the main queue with NULL on failure; the image is only borrowed, so
/// retain it to keep it past the block.
void SCCaptureWindow(CGWindowID windowID, void (^completion)(CGImageRef _Nullable image));

/// On-screen windows, front-most first, excluding this app's own windows.
/// Each entry has `windowID` (NSNumber), `bounds` (NSValue/CGRect in global
/// top-left coordinates) and `owner` (NSString).
NSArray<NSDictionary *> *SCOnScreenWindows(void);

/// Takes this app's own windows off the screen so a capture started from one of
/// them shows what was underneath. Returns them front-to-back for
/// SCRestoreOwnWindows; the menu bar item and anything else above normal window
/// level are left alone.
NSArray<NSWindow *> *SCHideOwnWindows(void);

/// Puts back what SCHideOwnWindows took away, in their original order.
void SCRestoreOwnWindows(NSArray<NSWindow *> *windows);

/// How long to wait after hiding before the screen is worth snapshotting.
/// -orderOut: returns before the window server has composited the window away.
extern const NSTimeInterval SCWindowHideSettleDelay;

NS_ASSUME_NONNULL_END
