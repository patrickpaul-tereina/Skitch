// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#import "ui/EditorWindowController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <memory>

#include "model/Document.h"
#include "render/Renderer.h"
#include "ui/CanvasView.h"
#include "ui/ToolPalette.h"
#include "util/ImageIO.h"

using sk::Tool;

// A clip view that keeps a small document centred instead of pinning it to a
// corner.
@interface SKCenteringClipView : NSClipView
@end

@implementation SKCenteringClipView
- (NSRect)constrainBoundsRect:(NSRect)proposed {
    NSRect rect = [super constrainBoundsRect:proposed];
    NSView *doc = self.documentView;
    if (!doc) return rect;
    const NSRect docFrame = doc.frame;
    if (docFrame.size.width < rect.size.width) {
        rect.origin.x = floor((docFrame.size.width - rect.size.width) * 0.5);
    }
    if (docFrame.size.height < rect.size.height) {
        rect.origin.y = floor((docFrame.size.height - rect.size.height) * 0.5);
    }
    return rect;
}
@end

@interface SKEditorWindowController () <NSWindowDelegate, SKCanvasViewDelegate,
                                        SKToolPaletteDelegate>
@end

@implementation SKEditorWindowController {
    std::unique_ptr<sk::Document> _document;
    SKCanvasView *_canvas;
    SKToolPalette *_palette;
    NSScrollView *_scrollView;
    NSTextField *_statusLabel;
    NSURL *_fileURL;
    NSString *_baseTitle;
}

// ============================================================== lifecycle ==

- (instancetype)initWithImage:(CGImageRef)image scale:(CGFloat)scale title:(NSString *)title {
    const size_t w = image ? CGImageGetWidth(image) : 800;
    const size_t h = image ? CGImageGetHeight(image) : 600;
    const CGFloat s = scale > 0 ? scale : 1.0;

    NSRect contentRect = NSMakeRect(0, 0, w / s, h / s + [SKToolPalette preferredHeight] + 22);
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:contentRect
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.minSize = NSMakeSize(1078, 360);  // the palette's controls need this much
    window.releasedWhenClosed = NO;
    window.tabbingMode = NSWindowTabbingModeDisallowed;

    if ((self = [super initWithWindow:window])) {
        window.delegate = self;
        _baseTitle = title.length ? title : @"Untitled Capture";
        _document = std::make_unique<sk::Document>();
        _document->reset(w, h);

        [self buildInterface];
        [_canvas loadImage:image scale:s];
        [self updateTitle];
        [self sizeWindowToImage];
    }
    return self;
}

- (void)dealloc {
    // The canvas only borrows the document, and the window can outlive this
    // controller by a display pass or two. Detach it so it draws nothing rather
    // than reading a freed document.
    _canvas.document = nullptr;
}

- (void)buildInterface {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;

    _palette = [[SKToolPalette alloc] initWithFrame:NSZeroRect];
    _palette.delegate = self;
    [content addSubview:_palette];

    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = YES;
    _scrollView.backgroundColor = [NSColor colorWithWhite:0.24 alpha:1.0];
    _scrollView.contentView = [[SKCenteringClipView alloc] initWithFrame:NSZeroRect];
    [content addSubview:_scrollView];

    _canvas = [[SKCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    _canvas.delegate = self;
    _canvas.document = _document.get();
    _canvas.currentTool = Tool::Arrow;
    _canvas.strokeColor = _palette.color;
    _canvas.lineWidth = _palette.lineWidth;
    _canvas.fontSize = _palette.fontSize;
    _canvas.fillShapes = _palette.fillShapes;
    _scrollView.documentView = _canvas;

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [content addSubview:_statusLabel];

    [self.window registerForDraggedTypes:@[ NSPasteboardTypeFileURL, NSPasteboardTypeTIFF ]];
    [self layoutContent];
}

- (void)layoutContent {
    NSView *content = self.window.contentView;
    const NSRect b = content.bounds;
    const CGFloat paletteH = [SKToolPalette preferredHeight];
    const CGFloat statusH = 22.0;

    _palette.frame = NSMakeRect(0, b.size.height - paletteH, b.size.width, paletteH);
    _statusLabel.frame = NSMakeRect(12, 4, b.size.width - 24, 14);
    _scrollView.frame = NSMakeRect(0, statusH, b.size.width,
                                   std::max<CGFloat>(0, b.size.height - paletteH - statusH));
    [_palette setNeedsLayout:YES];
}

- (void)sizeWindowToImage {
    NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
    const NSRect visible = screen.visibleFrame;

    const CGFloat paletteH = [SKToolPalette preferredHeight];
    const CGFloat chrome = paletteH + 22.0;

    const CGFloat maxW = visible.size.width * 0.86;
    const CGFloat maxH = visible.size.height * 0.86 - chrome;

    [_canvas zoomToFitInSize:NSMakeSize(maxW, maxH)];

    NSSize canvasSize = _canvas.frame.size;
    NSSize contentSize = NSMakeSize(std::max<CGFloat>(canvasSize.width, 1010),
                                    canvasSize.height + chrome);

    NSRect frame = [self.window frameRectForContentRect:NSMakeRect(0, 0, contentSize.width,
                                                                   contentSize.height)];
    frame.origin.x = visible.origin.x + (visible.size.width - frame.size.width) * 0.5;
    frame.origin.y = visible.origin.y + (visible.size.height - frame.size.height) * 0.65;
    [self.window setFrame:frame display:YES];
    [self layoutContent];
}

- (void)showAndFocus {
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:_canvas];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)updateTitle {
    NSString *name = _fileURL ? _fileURL.lastPathComponent : _baseTitle;
    self.window.title = [NSString stringWithFormat:@"%@ — Skitch", name];
    self.window.documentEdited = _document && _document->isDirty();
    [_palette setUndoEnabled:_document && _document->canUndo()
                 redoEnabled:_document && _document->canRedo()];
}

// ------------------------------------------------------ NSWindowDelegate ---

- (void)windowDidResize:(NSNotification *)notification { [self layoutContent]; }

- (void)windowWillClose:(NSNotification *)notification {
    [_canvas commitPendingEdits];
    [self.editorDelegate editorWindowControllerDidClose:self];
}

// ----------------------------------------------------- SKCanvasViewDelegate

- (void)canvasViewDidEditDocument:(SKCanvasView *)canvas { [self updateTitle]; }

- (void)canvasViewDidResizeDocument:(SKCanvasView *)canvas { [self layoutContent]; }

- (void)canvasView:(SKCanvasView *)canvas didUpdateStatus:(NSString *)status {
    _statusLabel.stringValue = status;
}

- (void)canvasViewDidFinishOneShotTool:(SKCanvasView *)canvas {
    _palette.tool = Tool::Select;
    _canvas.currentTool = Tool::Select;
}

// ---------------------------------------------------- SKToolPaletteDelegate

- (void)toolPaletteDidChangeTool:(SKToolPalette *)palette {
    _canvas.currentTool = palette.tool;
    [self.window makeFirstResponder:_canvas];
}

- (void)toolPaletteDidChangeStyle:(SKToolPalette *)palette {
    _canvas.strokeColor = palette.color;
    _canvas.lineWidth = palette.lineWidth;
    _canvas.fontSize = palette.fontSize;
    _canvas.fillShapes = palette.fillShapes;
}

- (void)toolPaletteDidRequestCapture:(SKToolPalette *)palette {
    [self.editorDelegate editorWindowControllerRequestsNewCapture:self];
}

- (void)toolPaletteDidRequestCopy:(SKToolPalette *)palette { [self copy:nil]; }
- (void)toolPaletteDidRequestSave:(SKToolPalette *)palette { [self saveDocument:nil]; }
- (void)toolPaletteDidRequestUndo:(SKToolPalette *)palette { [self undoEdit:nil]; }
- (void)toolPaletteDidRequestRedo:(SKToolPalette *)palette { [self redoEdit:nil]; }

// =============================================================== actions ===

// NSWindow itself implements undo:/redo: (forwarding to its NSUndoManager) and
// sits ahead of the window controller in the responder chain, so menu items
// wired to those selectors never reach us. Hence the distinct names.
- (void)undoEdit:(id)sender {
    [_canvas commitPendingEdits];
    _document->undo();
    [_canvas deselect];
    [_canvas refreshLayout];
    [self updateTitle];
}

- (void)redoEdit:(id)sender {
    [_canvas commitPendingEdits];
    _document->redo();
    [_canvas deselect];
    [_canvas refreshLayout];
    [self updateTitle];
}

- (void)copy:(id)sender {
    CGImageRef flat = [_canvas createFlattenedImage];
    if (!flat) return;
    SKCopyImageToPasteboard(flat);
    CGImageRelease(flat);
    _statusLabel.stringValue = @"Copied to clipboard";
}

- (void)saveDocument:(id)sender {
    if (_fileURL) {
        [self writeToURL:_fileURL];
        return;
    }
    [self saveDocumentAs:sender];
}

- (void)saveDocumentAs:(id)sender {
    [_canvas commitPendingEdits];

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = _fileURL.lastPathComponent ?: SKSuggestedFileName();
    panel.canCreateDirectories = YES;
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[ UTTypePNG, UTTypeJPEG, UTTypeTIFF ];
    }

    __weak SKEditorWindowController *weakSelf = self;
    [panel beginSheetModalForWindow:self.window
                  completionHandler:^(NSModalResponse response) {
                      if (response != NSModalResponseOK) return;
                      [weakSelf writeToURL:panel.URL];
                  }];
}

- (void)writeToURL:(NSURL *)url {
    CGImageRef flat = [_canvas createFlattenedImage];
    if (!flat) return;

    NSError *error = nil;
    const BOOL ok = SKWriteImage(flat, url, &error);
    CGImageRelease(flat);

    if (!ok) {
        [[NSAlert alertWithError:error] beginSheetModalForWindow:self.window
                                              completionHandler:nil];
        return;
    }

    _fileURL = url;
    _document->markClean();
    [self updateTitle];
    _statusLabel.stringValue = [NSString stringWithFormat:@"Saved to %@", url.path];
}

- (void)revealInFinder:(id)sender {
    if (!_fileURL) return;
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ _fileURL ]];
}

- (void)delete:(id)sender { [_canvas deleteSelection]; }
- (void)selectAll:(id)sender { [_canvas selectAll]; }
- (void)deleteAllAnnotations:(id)sender { [_canvas deleteAllAnnotations]; }
- (void)bringForward:(id)sender { [_canvas bringSelectionForward]; }
- (void)sendBackward:(id)sender { [_canvas sendSelectionBackward]; }
- (void)resetCrop:(id)sender { [_canvas resetCrop]; }
- (void)revertToOriginal:(id)sender { [_canvas revertToOriginal]; }

- (void)zoomIn:(id)sender { [_canvas zoomIn]; }
- (void)zoomOut:(id)sender { [_canvas zoomOut]; }
- (void)zoomActualSize:(id)sender { [_canvas zoomToActualSize]; }

- (void)zoomToFit:(id)sender {
    [_canvas zoomToFitInSize:_scrollView.contentView.bounds.size];
}

- (void)selectToolFromMenu:(NSMenuItem *)item {
    const Tool t = static_cast<Tool>(item.tag);
    _palette.tool = t;
    _canvas.currentTool = t;
}

// ---------------------------------------------------------- menu enabling --

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    const SEL action = item.action;

    // While the inline text editor is up, let plain-letter keystrokes reach it
    // instead of being swallowed by the Tools menu.
    if (action == @selector(selectToolFromMenu:)) {
        if (_canvas.isEditingText) return NO;
        item.state = (_canvas.currentTool == static_cast<Tool>(item.tag))
                         ? NSControlStateValueOn
                         : NSControlStateValueOff;
        return YES;
    }

    // Disabled while the inline text editor is up so that ⌘Z reaches the field
    // editor and undoes typing instead of the whole annotation.
    if (action == @selector(undoEdit:)) {
        return !_canvas.isEditingText && _document && _document->canUndo();
    }
    if (action == @selector(redoEdit:)) {
        return !_canvas.isEditingText && _document && _document->canRedo();
    }
    if (action == @selector(resetCrop:)) {
        return !_canvas.isEditingText && _document && _document->isCropped();
    }
    if (action == @selector(revertToOriginal:)) {
        return !_canvas.isEditingText && _document && _document->hasEdits();
    }
    if (action == @selector(delete:) || action == @selector(bringForward:) ||
        action == @selector(sendBackward:)) {
        return _canvas.selectedAnnotationID != 0;
    }
    if (action == @selector(deleteAllAnnotations:)) return _document && _document->count() > 0;
    if (action == @selector(revealInFinder:)) return _fileURL != nil;
    return YES;
}

// ------------------------------------------------------------ drag & drop --

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    NSArray *urls = [pb readObjectsForClasses:@[ [NSURL class] ]
                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
    NSURL *url = urls.firstObject;
    if (!url) return NO;

    CGImageRef img = SKReadImage(url);
    if (!img) return NO;

    _document->reset(CGImageGetWidth(img), CGImageGetHeight(img));
    [_canvas loadImage:img scale:1.0];
    CGImageRelease(img);

    _fileURL = url;
    [self updateTitle];
    [self sizeWindowToImage];
    return YES;
}

@end
