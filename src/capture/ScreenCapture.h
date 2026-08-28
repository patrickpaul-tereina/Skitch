// Thin wrapper over the CoreGraphics window/display capture APIs, plus the
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

/// Full-resolution grab of a single display. Caller owns the result.
CGImageRef _Nullable SCCaptureDisplay(CGDirectDisplayID display);

/// One snapshot per attached display.
NSArray<SCDisplaySnapshot *> *SCSnapshotAllDisplays(void);

/// Full-resolution grab of one window, excluding its shadow. Caller owns it.
CGImageRef _Nullable SCCaptureWindow(CGWindowID windowID);

/// On-screen windows, front-most first, excluding this app's own windows.
/// Each entry has `windowID` (NSNumber), `bounds` (NSValue/CGRect in global
/// top-left coordinates) and `owner` (NSString).
NSArray<NSDictionary *> *SCOnScreenWindows(void);

NS_ASSUME_NONNULL_END
