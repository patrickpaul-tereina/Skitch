// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
// One window per capture: palette on top, canvas in a scroll view, status bar
// at the bottom.
#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SKEditorWindowController;

@protocol SKEditorWindowControllerDelegate <NSObject>
- (void)editorWindowControllerDidClose:(SKEditorWindowController *)controller;
- (void)editorWindowControllerRequestsNewCapture:(SKEditorWindowController *)controller;
@end

@interface SKEditorWindowController : NSWindowController

@property(nonatomic, weak) id<SKEditorWindowControllerDelegate> editorDelegate;

/// Takes ownership of `image` (retains it).
- (instancetype)initWithImage:(CGImageRef)image
                        scale:(CGFloat)scale
                        title:(nullable NSString *)title;

- (void)showAndFocus;

@end

NS_ASSUME_NONNULL_END
