// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#import <AppKit/AppKit.h>

#import "ui/AppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        // NSApplication holds its delegate weakly, so keep a strong reference
        // alive for the lifetime of the process.
        static SKAppDelegate *delegate = nil;
        delegate = [[SKAppDelegate alloc] init];
        app.delegate = delegate;

        [app run];
    }
    return 0;
}
