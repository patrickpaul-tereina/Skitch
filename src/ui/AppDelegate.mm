#import "ui/AppDelegate.h"

#import <Carbon/Carbon.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <cstdio>

#include "capture/OverlayWindow.h"
#include "capture/ScreenCapture.h"
#include "model/Annotation.h"
#include "ui/EditorWindowController.h"
#include "util/Hotkeys.h"
#include "util/ImageIO.h"

using sk::Tool;

@interface SKAppDelegate () <SKEditorWindowControllerDelegate>
@end

@implementation SKAppDelegate {
    NSMutableArray<SKEditorWindowController *> *_editors;
    NSStatusItem *_statusItem;
}

// ============================================================== app cycle ==

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _editors = [NSMutableArray array];

    [self buildMainMenu];
    [self buildStatusItem];
    [self registerGlobalHotkeys];

    NSString *selfTestPath = [self commandLineValueForOption:@"--selftest"];
    if (selfTestPath) {
        [self runSelfTestWritingTo:selfTestPath];
        return;
    }

    if ([self openFilesFromCommandLine]) return;
    if ([self commandLineHasFlag:@"--no-capture"]) return;

    if (!SCHasScreenRecordingPermission()) {
        // Ask up front: without this every capture silently returns wallpaper.
        SCRequestScreenRecordingPermission();
        if (!SCHasScreenRecordingPermission()) {
            SCShowPermissionAlert();
            return;
        }
    }

    [self captureRegion:nil];
}

- (BOOL)commandLineHasFlag:(NSString *)flag {
    return [[NSProcessInfo processInfo].arguments containsObject:flag];
}

- (NSString *)commandLineValueForOption:(NSString *)option {
    NSArray<NSString *> *args = [NSProcessInfo processInfo].arguments;
    const NSUInteger i = [args indexOfObject:option];
    if (i == NSNotFound || i + 1 >= args.count) return nil;
    return args[i + 1];
}

/// Builds a real editor window, renders its content off-screen to a PNG and
/// quits. Exercises the whole AppKit path without needing Screen Recording.
- (void)runSelfTestWritingTo:(NSString *)path {
    NSString *imagePath = nil;
    for (NSString *arg in [NSProcessInfo processInfo].arguments) {
        if ([arg hasSuffix:@".png"] && ![arg isEqualToString:path] &&
            [[NSFileManager defaultManager] fileExistsAtPath:arg]) {
            imagePath = arg;
            break;
        }
    }
    if (!imagePath || ![self openImageAtURL:[NSURL fileURLWithPath:imagePath]]) {
        std::fputs("selftest: could not open a source image\n", stderr);
        [NSApp terminate:nil];
        return;
    }

    SKEditorWindowController *editor = _editors.lastObject;
    NSView *content = editor.window.contentView;

    // One turn of the run loop so layout and first display settle.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [content displayIfNeeded];
                       NSBitmapImageRep *rep =
                           [content bitmapImageRepForCachingDisplayInRect:content.bounds];
                       [content cacheDisplayInRect:content.bounds toBitmapImageRep:rep];
                       NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                                       properties:@{}];
                       const BOOL ok = [png writeToFile:path atomically:YES];
                       std::fprintf(stderr, "selftest: %s %s (%.0fx%.0f)\n",
                                    ok ? "wrote" : "FAILED to write", path.UTF8String,
                                    content.bounds.size.width, content.bounds.size.height);
                       [NSApp terminate:nil];
                   });
}

/// Opens any image paths passed on the command line. Returns YES if at least
/// one opened, in which case launch should not start a capture.
- (BOOL)openFilesFromCommandLine {
    NSArray<NSString *> *args = [NSProcessInfo processInfo].arguments;
    BOOL opened = NO;
    for (NSUInteger i = 1; i < args.count; ++i) {
        NSString *arg = args[i];
        if ([arg hasPrefix:@"-"]) continue;  // flags, and Xcode's -NSDocument…
        if (![[NSFileManager defaultManager] fileExistsAtPath:arg]) continue;
        if ([self openImageAtURL:[NSURL fileURLWithPath:arg]]) opened = YES;
    }
    return opened;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[SKHotkeyManager shared] unregisterAll];
}

- (BOOL)application:(NSApplication *)application openFile:(NSString *)filename {
    return [self openImageAtURL:[NSURL fileURLWithPath:filename]];
}

// ================================================================== menus ==

- (NSMenuItem *)addItemTo:(NSMenu *)menu
                    title:(NSString *)title
                   action:(SEL _Nullable)action
                      key:(NSString *)key
                modifiers:(NSEventModifierFlags)modifiers {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = modifiers;
    [menu addItem:item];
    return item;
}

- (void)buildMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    // ---- Application ----
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    appItem.submenu = appMenu;

    [self addItemTo:appMenu
              title:@"About Skitch"
             action:@selector(orderFrontStandardAboutPanel:)
                key:@""
          modifiers:0];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:appMenu
              title:@"Screen Recording Permission…"
             action:@selector(showPermissionHelp:)
                key:@""
          modifiers:0];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:appMenu
              title:@"Hide Skitch"
             action:@selector(hide:)
                key:@"h"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:appMenu
              title:@"Hide Others"
             action:@selector(hideOtherApplications:)
                key:@"h"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagOption];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:appMenu
              title:@"Quit Skitch"
             action:@selector(terminate:)
                key:@"q"
          modifiers:NSEventModifierFlagCommand];

    // ---- File ----
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    fileItem.submenu = fileMenu;

    [self addItemTo:fileMenu
              title:@"Capture Region…"
             action:@selector(captureRegion:)
                key:@"r"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:fileMenu
              title:@"Capture Window…"
             action:@selector(captureWindow:)
                key:@"r"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [self addItemTo:fileMenu
              title:@"Capture Full Screen"
             action:@selector(captureFullScreen:)
                key:@"r"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagOption];
    [self addItemTo:fileMenu
              title:@"Capture Region After 5s"
             action:@selector(captureRegionDelayed:)
                key:@"r"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagControl];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:fileMenu
              title:@"Open Image…"
             action:@selector(openImage:)
                key:@"o"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:fileMenu
              title:@"New from Clipboard"
             action:@selector(newFromClipboard:)
                key:@"v"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:fileMenu
              title:@"Save"
             action:@selector(saveDocument:)
                key:@"s"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:fileMenu
              title:@"Save As…"
             action:@selector(saveDocumentAs:)
                key:@"s"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [self addItemTo:fileMenu
              title:@"Reveal in Finder"
             action:@selector(revealInFinder:)
                key:@"r"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift |
                    NSEventModifierFlagOption];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:fileMenu
              title:@"Close Window"
             action:@selector(performClose:)
                key:@"w"
          modifiers:NSEventModifierFlagCommand];

    // ---- Edit ----
    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    editItem.submenu = editMenu;

    // undoEdit:/redoEdit: rather than undo:/redo: — NSWindow implements the
    // latter and would intercept them ahead of the window controller.
    [self addItemTo:editMenu
              title:@"Undo"
             action:@selector(undoEdit:)
                key:@"z"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:editMenu
              title:@"Redo"
             action:@selector(redoEdit:)
                key:@"z"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [self addItemTo:editMenu
              title:@"Revert to Original"
             action:@selector(revertToOriginal:)
                key:@"z"
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagOption];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:editMenu
              title:@"Copy Image"
             action:@selector(copy:)
                key:@"c"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:editMenu
              title:@"Paste"
             action:@selector(paste:)
                key:@"v"
          modifiers:NSEventModifierFlagCommand];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:editMenu
              title:@"Delete Mark"
             action:@selector(delete:)
                key:@""
          modifiers:0];
    [self addItemTo:editMenu
              title:@"Select Last Mark"
             action:@selector(selectAll:)
                key:@"a"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:editMenu
              title:@"Delete All Marks"
             action:@selector(deleteAllAnnotations:)
                key:@""
          modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:editMenu
              title:@"Bring Forward"
             action:@selector(bringForward:)
                key:@"]"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:editMenu
              title:@"Send Backward"
             action:@selector(sendBackward:)
                key:@"["
          modifiers:NSEventModifierFlagCommand];

    // ---- Tools ----
    NSMenuItem *toolsItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:toolsItem];
    NSMenu *toolsMenu = [[NSMenu alloc] initWithTitle:@"Tools"];
    toolsItem.submenu = toolsMenu;

    struct {
        const char *title;
        Tool tool;
        const char *key;
    } tools[] = {
        {"Select", Tool::Select, "v"},      {"Arrow", Tool::Arrow, "a"},
        {"Line", Tool::Line, "l"},          {"Rectangle", Tool::Rect, "r"},
        {"Ellipse", Tool::Ellipse, "o"},    {"Pen", Tool::Pen, "p"},
        {"Highlighter", Tool::Highlighter, "h"}, {"Text", Tool::Text, "t"},
        {"Pixelate", Tool::Pixelate, "x"},  {"Crop", Tool::Crop, "c"},
    };
    for (const auto &t : tools) {
        NSMenuItem *item = [self addItemTo:toolsMenu
                                     title:@(t.title)
                                    action:@selector(selectToolFromMenu:)
                                       key:@(t.key)
                                 modifiers:0];
        item.tag = static_cast<NSInteger>(t.tool);
    }
    [toolsMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:toolsMenu
              title:@"Reset Crop"
             action:@selector(resetCrop:)
                key:@""
          modifiers:0];

    // ---- View ----
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    viewItem.submenu = viewMenu;

    // "=" so that plain ⌘= zooms in; the shifted "+" is a hidden alternate.
    [self addItemTo:viewMenu
              title:@"Zoom In"
             action:@selector(zoomIn:)
                key:@"="
          modifiers:NSEventModifierFlagCommand];
    NSMenuItem *zoomInAlt = [self addItemTo:viewMenu
                                      title:@"Zoom In"
                                     action:@selector(zoomIn:)
                                        key:@"+"
                                  modifiers:NSEventModifierFlagCommand |
                                            NSEventModifierFlagShift];
    zoomInAlt.hidden = YES;
    zoomInAlt.allowsKeyEquivalentWhenHidden = YES;
    [self addItemTo:viewMenu
              title:@"Zoom Out"
             action:@selector(zoomOut:)
                key:@"-"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:viewMenu
              title:@"Actual Size"
             action:@selector(zoomActualSize:)
                key:@"0"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:viewMenu
              title:@"Zoom to Fit"
             action:@selector(zoomToFit:)
                key:@"9"
          modifiers:NSEventModifierFlagCommand];

    // ---- Window ----
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    windowItem.submenu = windowMenu;
    [self addItemTo:windowMenu
              title:@"Minimize"
             action:@selector(performMiniaturize:)
                key:@"m"
          modifiers:NSEventModifierFlagCommand];
    [self addItemTo:windowMenu
              title:@"Bring All to Front"
             action:@selector(arrangeInFront:)
                key:@""
          modifiers:0];

    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
}

- (void)buildStatusItem {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    if (@available(macOS 11.0, *)) {
        _statusItem.button.image =
            [NSImage imageWithSystemSymbolName:@"camera.viewfinder"
                      accessibilityDescription:@"Skitch"];
    } else {
        _statusItem.button.title = @"◲";
    }
    _statusItem.button.toolTip = @"Skitch";

    NSMenu *menu = [[NSMenu alloc] init];
    [self addItemTo:menu title:@"Capture Region" action:@selector(captureRegion:) key:@"" modifiers:0];
    [self addItemTo:menu title:@"Capture Window" action:@selector(captureWindow:) key:@"" modifiers:0];
    [self addItemTo:menu title:@"Capture Full Screen" action:@selector(captureFullScreen:) key:@"" modifiers:0];
    [self addItemTo:menu title:@"Capture Region After 5s" action:@selector(captureRegionDelayed:) key:@"" modifiers:0];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:menu title:@"Open Image…" action:@selector(openImage:) key:@"" modifiers:0];
    [self addItemTo:menu title:@"New from Clipboard" action:@selector(newFromClipboard:) key:@"" modifiers:0];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:menu title:@"Quit Skitch" action:@selector(terminate:) key:@"" modifiers:0];

    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(terminate:)) continue;
        item.target = self;
    }
    _statusItem.menu = menu;
}

- (void)registerGlobalHotkeys {
    SKHotkeyManager *hk = [SKHotkeyManager shared];
    const uint32_t mods = cmdKey | optionKey | controlKey;

    __weak SKAppDelegate *weakSelf = self;
    [hk registerKeyCode:kVK_ANSI_R
              modifiers:mods
             identifier:1
                handler:^{
                    [weakSelf captureRegion:nil];
                }];
    [hk registerKeyCode:kVK_ANSI_W
              modifiers:mods
             identifier:2
                handler:^{
                    [weakSelf captureWindow:nil];
                }];
}

// =============================================================== capture ===

- (void)beginCapture:(SCCaptureMode)mode delay:(NSTimeInterval)delay {
    if ([SCOverlayController isCapturing]) return;

    __weak SKAppDelegate *weakSelf = self;
    [SCOverlayController beginCaptureWithMode:mode
                                        delay:delay
                                   completion:^(CGImageRef image, CGFloat scale) {
                                       if (!image) return;
                                       [weakSelf openEditorWithImage:image
                                                               scale:scale
                                                               title:nil];
                                       CGImageRelease(image);
                                   }];
}

- (void)captureRegion:(id)sender { [self beginCapture:SCCaptureModeRegion delay:0]; }
- (void)captureWindow:(id)sender { [self beginCapture:SCCaptureModeWindow delay:0]; }
- (void)captureFullScreen:(id)sender { [self beginCapture:SCCaptureModeFullScreen delay:0]; }
- (void)captureRegionDelayed:(id)sender { [self beginCapture:SCCaptureModeRegion delay:5.0]; }

- (void)showPermissionHelp:(id)sender { SCShowPermissionAlert(); }

// ================================================================= files ===

- (void)openImage:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[ UTTypeImage ];
    }
    if ([panel runModal] != NSModalResponseOK) return;
    [self openImageAtURL:panel.URL];
}

- (BOOL)openImageAtURL:(NSURL *)url {
    CGImageRef img = SKReadImage(url);
    if (!img) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Could not open that image.";
        alert.informativeText = url.lastPathComponent ?: @"";
        [alert runModal];
        return NO;
    }
    [self openEditorWithImage:img scale:1.0 title:url.lastPathComponent];
    CGImageRelease(img);
    return YES;
}

- (void)newFromClipboard:(id)sender {
    CGImageRef img = SKImageFromPasteboard();
    if (!img) {
        NSBeep();
        return;
    }
    [self openEditorWithImage:img scale:1.0 title:@"Clipboard"];
    CGImageRelease(img);
}

- (void)openEditorWithImage:(CGImageRef)image scale:(CGFloat)scale title:(NSString *)title {
    SKEditorWindowController *editor =
        [[SKEditorWindowController alloc] initWithImage:image scale:scale title:title];
    editor.editorDelegate = self;
    [_editors addObject:editor];
    [editor showAndFocus];
}

// -------------------------------------------- SKEditorWindowControllerDelegate

- (void)editorWindowControllerDidClose:(SKEditorWindowController *)controller {
    [_editors removeObject:controller];
}

- (void)editorWindowControllerRequestsNewCapture:(SKEditorWindowController *)controller {
    [self captureRegion:nil];
}

@end
