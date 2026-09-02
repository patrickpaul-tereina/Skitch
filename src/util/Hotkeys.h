// SPDX-FileCopyrightText: 2026 Kunkka
// SPDX-License-Identifier: GPL-2.0-only
// System-wide hotkeys via Carbon's RegisterEventHotKey. Unlike NSEvent global
// monitors this needs no Accessibility permission, which matters for a capture
// tool that should work the moment it launches.
#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SKHotkeyManager : NSObject

+ (instancetype)shared;

/// `keyCode` is a virtual key code (kVK_ANSI_*), `modifiers` a Carbon mask
/// (cmdKey / shiftKey / optionKey / controlKey).
- (BOOL)registerKeyCode:(uint32_t)keyCode
              modifiers:(uint32_t)modifiers
             identifier:(uint32_t)identifier
                handler:(void (^)(void))handler;

- (void)unregisterAll;

@end

NS_ASSUME_NONNULL_END
