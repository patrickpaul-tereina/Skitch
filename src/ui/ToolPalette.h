// The strip of controls above the canvas: tool picker, colour, size, fill and
// the capture / copy / save shortcuts.
#pragma once

#import <AppKit/AppKit.h>

#include "model/Annotation.h"

NS_ASSUME_NONNULL_BEGIN

@class SKToolPalette;

@protocol SKToolPaletteDelegate <NSObject>
- (void)toolPaletteDidChangeTool:(SKToolPalette *)palette;
- (void)toolPaletteDidChangeStyle:(SKToolPalette *)palette;
- (void)toolPaletteDidRequestCapture:(SKToolPalette *)palette;
- (void)toolPaletteDidRequestCopy:(SKToolPalette *)palette;
- (void)toolPaletteDidRequestSave:(SKToolPalette *)palette;
- (void)toolPaletteDidRequestUndo:(SKToolPalette *)palette;
- (void)toolPaletteDidRequestRedo:(SKToolPalette *)palette;
@end

@interface SKToolPalette : NSView

@property(nonatomic, weak) id<SKToolPaletteDelegate> delegate;

@property(nonatomic) sk::Tool tool;
@property(nonatomic, strong) NSColor *color;
/// Stroke width in points, before the capture-scale multiplier.
@property(nonatomic) CGFloat lineWidth;
@property(nonatomic) CGFloat fontSize;
@property(nonatomic) BOOL fillShapes;

+ (CGFloat)preferredHeight;

- (void)setUndoEnabled:(BOOL)undoEnabled redoEnabled:(BOOL)redoEnabled;

@end

NS_ASSUME_NONNULL_END
