// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
// The editing surface: draws the document, runs the tool interactions and
// hosts the inline text editor.
#pragma once

#import <AppKit/AppKit.h>

#include "model/Document.h"

NS_ASSUME_NONNULL_BEGIN

@class SKCanvasView;

@protocol SKCanvasViewDelegate <NSObject>
/// The document changed in a way that affects undo state / dirty flag.
- (void)canvasViewDidEditDocument:(SKCanvasView *)canvas;
/// The document's visible size changed (crop) — the window may want to resize.
- (void)canvasViewDidResizeDocument:(SKCanvasView *)canvas;
/// Short status string for the footer.
- (void)canvasView:(SKCanvasView *)canvas didUpdateStatus:(NSString *)status;
/// A tool finished a one-shot action (crop) and the palette should fall back
/// to Select.
- (void)canvasViewDidFinishOneShotTool:(SKCanvasView *)canvas;
@end

@interface SKCanvasView : NSView

@property(nonatomic, weak) id<SKCanvasViewDelegate> delegate;

/// Not owned; the window controller keeps it alive for the view's lifetime.
@property(nonatomic, assign) sk::Document *document;

/// Base pixels. Setting this retains the image and releases the previous one.
@property(nonatomic) CGImageRef baseImage;
/// Pixels per point of the capture (2.0 for a Retina grab).
@property(nonatomic) CGFloat captureScale;

@property(nonatomic) sk::Tool currentTool;
@property(nonatomic, strong) NSColor *strokeColor;
@property(nonatomic) CGFloat lineWidth;
@property(nonatomic) CGFloat fontSize;
@property(nonatomic) BOOL fillShapes;

/// 1.0 == 100%.
@property(nonatomic) CGFloat zoomLevel;

@property(nonatomic, readonly) int selectedAnnotationID;
/// YES while the inline text editor has focus.
@property(nonatomic, readonly) BOOL isEditingText;

- (void)loadImage:(CGImageRef)image scale:(CGFloat)scale;

- (void)zoomIn;
- (void)zoomOut;
- (void)zoomToActualSize;
- (void)zoomToFitInSize:(NSSize)available;

- (void)deleteSelection;
- (void)selectAll;
- (void)deselect;
- (void)bringSelectionForward;
- (void)sendSelectionBackward;
- (void)deleteAllAnnotations;
- (void)resetCrop;
/// Discards every mark and the crop, in one undoable step.
- (void)revertToOriginal;

/// Commits any in-progress text edit. Call before saving/copying/undoing.
- (void)commitPendingEdits;

/// Flattened output, caller owns it.
- (CGImageRef _Nullable)createFlattenedImage;

/// Recomputes the frame after zoom or crop changes.
- (void)refreshLayout;

@end

NS_ASSUME_NONNULL_END
