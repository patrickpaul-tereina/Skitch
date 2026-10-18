// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
#import "capture/CountdownWindow.h"

#import "capture/ScreenCapture.h"

static const CGFloat kBadgeDiameter = 150.0;

// ------------------------------------------------------------------ view ---

@interface SCCountdownView : NSView
@property(nonatomic) NSInteger value;
@end

@implementation SCCountdownView

- (void)setValue:(NSInteger)value {
    _value = value;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty {
    const NSRect disc = NSInsetRect(self.bounds, 4.0, 4.0);

    // The same red as the default annotation colour, mostly see-through so the
    // badge does not hide what is being lined up. The number stays opaque.
    [[NSColor colorWithRed:0.93 green:0.16 blue:0.16 alpha:0.6] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:disc] fill];

    NSDictionary *attrs = @{
        NSFontAttributeName : [NSFont monospacedDigitSystemFontOfSize:kBadgeDiameter * 0.5
                                                                weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : [NSColor whiteColor],
    };
    NSString *text = [NSString stringWithFormat:@"%ld", (long)self.value];
    const NSSize size = [text sizeWithAttributes:attrs];
    [text drawAtPoint:NSMakePoint(NSMidX(disc) - size.width * 0.5,
                                  NSMidY(disc) - size.height * 0.5)
       withAttributes:attrs];
}

@end

// ------------------------------------------------------------ controller ---

@implementation SCCountdown

+ (void)runForSeconds:(NSInteger)seconds completion:(void (^)(void))completion {
    if (seconds <= 0) {
        dispatch_async(dispatch_get_main_queue(), completion);
        return;
    }

    // The screen being worked on, which is where the user is looking.
    NSScreen *screen = [NSScreen mainScreen];
    const NSPoint mouse = [NSEvent mouseLocation];
    for (NSScreen *s in [NSScreen screens]) {
        if (NSPointInRect(mouse, s.frame)) screen = s;
    }
    const NSRect sf = screen.frame;
    const NSRect frame = NSMakeRect(NSMidX(sf) - kBadgeDiameter * 0.5,
                                    NSMidY(sf) - kBadgeDiameter * 0.5,
                                    kBadgeDiameter, kBadgeDiameter);

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskBorderless |
                                                          NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = NO;
    panel.ignoresMouseEvents = YES;
    panel.releasedWhenClosed = NO;
    // Above menus and full-screen apps, since opening one is often the reason
    // for a delayed capture in the first place.
    panel.level = NSScreenSaverWindowLevel;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorFullScreenAuxiliary |
                               NSWindowCollectionBehaviorStationary |
                               NSWindowCollectionBehaviorIgnoresCycle;

    SCCountdownView *view = [[SCCountdownView alloc]
        initWithFrame:NSMakeRect(0, 0, kBadgeDiameter, kBadgeDiameter)];
    view.value = seconds;
    panel.contentView = view;
    // Regardless: Skitch is usually not the active app, and must not become it.
    [panel orderFrontRegardless];

    __block NSInteger remaining = seconds;
    [NSTimer scheduledTimerWithTimeInterval:1.0
                                    repeats:YES
                                      block:^(NSTimer *timer) {
                                          if (--remaining > 0) {
                                              view.value = remaining;
                                              return;
                                          }
                                          [timer invalidate];
                                          [panel orderOut:nil];
                                          // -orderOut: returns before the window
                                          // server has composited the badge away.
                                          dispatch_after(
                                              dispatch_time(DISPATCH_TIME_NOW,
                                                            (int64_t)(SCWindowHideSettleDelay *
                                                                      NSEC_PER_SEC)),
                                              dispatch_get_main_queue(), completion);
                                      }];
}

@end
