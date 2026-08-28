// Full-screen selection overlay: freezes every display, dims them, and lets
// the user drag out a region or click a window to capture.
#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCCaptureMode) {
    SCCaptureModeRegion = 0,
    SCCaptureModeWindow,
    SCCaptureModeFullScreen,
};

/// Called with a retained CGImage the receiver takes ownership of, or NULL if
/// the user cancelled. `scale` is the image's pixels-per-point.
typedef void (^SCCaptureCompletion)(CGImageRef _Nullable image, CGFloat scale);

@interface SCOverlayController : NSObject

/// Presents the overlay (or captures immediately, for full-screen mode).
/// Does nothing if a capture session is already running.
+ (void)beginCaptureWithMode:(SCCaptureMode)mode
                       delay:(NSTimeInterval)delay
                  completion:(SCCaptureCompletion)completion;

+ (BOOL)isCapturing;

@end

NS_ASSUME_NONNULL_END
