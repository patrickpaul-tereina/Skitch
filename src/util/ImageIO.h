// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
// File and pasteboard I/O for flattened captures.
#pragma once

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Writes `image` to `url`, choosing the encoder from the path extension
/// (png, jpg/jpeg, tiff, heic; anything else falls back to PNG).
BOOL SKWriteImage(CGImageRef image, NSURL *url, NSError *_Nullable *_Nullable error);

/// Loads an image file. Caller owns the result.
CGImageRef _Nullable SKReadImage(NSURL *url);

/// Puts the image on the general pasteboard as both TIFF and PNG.
void SKCopyImageToPasteboard(CGImageRef image);

/// Reads an image off the general pasteboard, or NULL. Caller owns the result.
CGImageRef _Nullable SKImageFromPasteboard(void);

/// "Screenshot 2026-08-27 at 18.53.11.png" style name.
NSString *SKSuggestedFileName(void);

NS_ASSUME_NONNULL_END
