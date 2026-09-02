// Covers SCHideOwnWindows / SCRestoreOwnWindows — the "get out of the shot"
// step that runs before every capture.
//
// Two things here have real consequences and are easy to get wrong: ordering
// out the status bar item's window would take the menu bar icon away with it,
// and restoring in the wrong direction would shuffle the user's windows.
//
// The windows this test makes never get window-server backing (no window
// number, no compositing) — there is no session behind a test run. So the
// order NSApp reports cannot be trusted here, and the assertions below do not
// use it: they watch the messages the code under test actually sends, via a
// recording NSWindow subclass, and check NSWindow's own bookkeeping.

#import <AppKit/AppKit.h>

#include <cstdio>
#include <string>
#include <vector>

#include "capture/ScreenCapture.h"

static int gFailures = 0;

#define CHECK(cond)                                                                  \
    do {                                                                             \
        if (!(cond)) {                                                               \
            std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);              \
            ++gFailures;                                                             \
        }                                                                            \
    } while (0)

// ---------------------------------------------------------------------------

/// Records the ordering messages sent to it, so the test can assert on what the
/// code under test did rather than on window-server state that does not exist
/// in a headless run.
@interface SKRecordingWindow : NSWindow
@property(nonatomic, copy) NSString *tag;
@end

static std::vector<std::string> gOrderFrontLog;
static std::vector<std::string> gMadeKeyLog;

@implementation SKRecordingWindow

- (void)orderFront:(id)sender {
    gOrderFrontLog.push_back(self.tag.UTF8String);
    [super orderFront:sender];
}

- (void)makeKeyWindow {
    gMadeKeyLog.push_back(self.tag.UTF8String);
    // Deliberately not calling super: without a window server there is nothing
    // to make key, and AppKit logs about it.
}

@end

static SKRecordingWindow *MakeWindow(NSString *tag, NSWindowLevel level) {
    SKRecordingWindow *w =
        [[SKRecordingWindow alloc] initWithContentRect:NSMakeRect(0, 0, 240, 160)
                                             styleMask:NSWindowStyleMaskTitled
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    w.tag = tag;
    w.title = tag;
    w.level = level;
    w.releasedWhenClosed = NO;
    [w orderFront:nil];
    return w;
}

// ---------------------------------------------------------------------------

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        SKRecordingWindow *editorA = MakeWindow(@"editorA", NSNormalWindowLevel);
        SKRecordingWindow *editorB = MakeWindow(@"editorB", NSNormalWindowLevel);
        // Stands in for the NSStatusItem's window, which lives above the
        // document windows and must survive a capture.
        SKRecordingWindow *statusItem = MakeWindow(@"statusItem", NSStatusWindowLevel);
        SKRecordingWindow *offscreen = MakeWindow(@"offscreen", NSNormalWindowLevel);
        [offscreen orderOut:nil];

        CHECK(editorA.isVisible);
        CHECK(editorB.isVisible);
        CHECK(statusItem.isVisible);
        CHECK(!offscreen.isVisible);

        // ---- hiding ------------------------------------------------------

        gOrderFrontLog.clear();
        NSArray<NSWindow *> *hidden = SCHideOwnWindows();

        std::printf("hid %lu window(s):", (unsigned long)hidden.count);
        for (NSWindow *w in hidden) std::printf(" %s", w.title.UTF8String);
        std::printf("\n");

        CHECK(hidden.count == 2);
        CHECK([hidden containsObject:editorA]);
        CHECK([hidden containsObject:editorB]);

        // The two that must be left alone, for different reasons.
        CHECK(![hidden containsObject:statusItem]);
        CHECK(![hidden containsObject:offscreen]);

        CHECK(!editorA.isVisible);
        CHECK(!editorB.isVisible);
        CHECK(statusItem.isVisible);  // the menu bar icon is still there

        // ---- restoring ---------------------------------------------------

        gOrderFrontLog.clear();
        gMadeKeyLog.clear();
        SCRestoreOwnWindows(hidden);

        CHECK(editorA.isVisible);
        CHECK(editorB.isVisible);

        // Everything that was hidden is ordered back, and in reverse: the
        // caller's array runs front-to-back, so fronting it in that order would
        // leave the back-most window on top.
        CHECK(gOrderFrontLog.size() == hidden.count);
        if (gOrderFrontLog.size() == hidden.count) {
            for (std::size_t i = 0; i < gOrderFrontLog.size(); ++i) {
                NSWindow *expected = hidden[hidden.count - 1 - i];
                CHECK(gOrderFrontLog[i] == expected.title.UTF8String);
            }
        }

        // Focus goes back to the window that had it.
        CHECK(gMadeKeyLog.size() == 1);
        if (gMadeKeyLog.size() == 1) {
            CHECK(gMadeKeyLog[0] == [hidden.firstObject title].UTF8String);
        }

        // ---- nothing to restore -------------------------------------------
        // The common case: a capture from the menu bar with no editor open.
        gOrderFrontLog.clear();
        gMadeKeyLog.clear();
        SCRestoreOwnWindows(@[]);
        CHECK(gOrderFrontLog.empty());
        CHECK(gMadeKeyLog.empty());

        // A settle delay of zero would defeat the point of hiding at all.
        CHECK(SCWindowHideSettleDelay > 0.0);
    }

    if (gFailures) {
        std::printf("\n%d check(s) failed\n", gFailures);
        return 1;
    }
    std::printf("\nall checks passed\n");
    return 0;
}
