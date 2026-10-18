// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
// The on-screen countdown shown before a delayed capture: a round badge with
// the seconds remaining, centred on the screen under the mouse. It floats above
// everything, takes no clicks and never becomes key, so the user can keep
// arranging what they mean to capture while it runs.
#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCCountdown : NSObject

/// Counts down from `seconds` to 1, one per second, then takes the badge off
/// the screen and calls `completion` on the main queue once it is gone from
/// the display — safe to snapshot straight away.
+ (void)runForSeconds:(NSInteger)seconds completion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
