#import "util/Hotkeys.h"

#import <Carbon/Carbon.h>

static const OSType kSkitchHotkeySignature = 'SKCH';

@implementation SKHotkeyManager {
    NSMutableDictionary<NSNumber *, id> *_handlers;
    NSMutableArray *_refs;  // boxed EventHotKeyRef
    EventHandlerRef _eventHandler;
}

+ (instancetype)shared {
    static SKHotkeyManager *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[SKHotkeyManager alloc] init];
    });
    return shared;
}

static OSStatus HotkeyCallback(EventHandlerCallRef next, EventRef event, void *userData) {
    EventHotKeyID hotkeyID;
    const OSStatus status = GetEventParameter(event, kEventParamDirectObject,
                                              typeEventHotKeyID, NULL,
                                              sizeof(hotkeyID), NULL, &hotkeyID);
    if (status != noErr) return status;

    SKHotkeyManager *self_ = (__bridge SKHotkeyManager *)userData;
    [self_ fireHandlerForIdentifier:hotkeyID.id];
    return noErr;
}

- (instancetype)init {
    if ((self = [super init])) {
        _handlers = [NSMutableDictionary dictionary];
        _refs = [NSMutableArray array];

        EventTypeSpec spec = {kEventClassKeyboard, kEventHotKeyPressed};
        InstallApplicationEventHandler(&HotkeyCallback, 1, &spec, (__bridge void *)self,
                                       &_eventHandler);
    }
    return self;
}

- (void)fireHandlerForIdentifier:(uint32_t)identifier {
    void (^handler)(void) = _handlers[@(identifier)];
    if (handler) handler();
}

- (BOOL)registerKeyCode:(uint32_t)keyCode
              modifiers:(uint32_t)modifiers
             identifier:(uint32_t)identifier
                handler:(void (^)(void))handler {
    EventHotKeyID hotkeyID;
    hotkeyID.signature = kSkitchHotkeySignature;
    hotkeyID.id = identifier;

    EventHotKeyRef ref = NULL;
    const OSStatus status = RegisterEventHotKey(keyCode, modifiers, hotkeyID,
                                                GetApplicationEventTarget(), 0, &ref);
    if (status != noErr || !ref) return NO;

    _handlers[@(identifier)] = [handler copy];
    [_refs addObject:[NSValue valueWithPointer:ref]];
    return YES;
}

- (void)unregisterAll {
    for (NSValue *v in _refs) {
        EventHotKeyRef ref = (EventHotKeyRef)v.pointerValue;
        if (ref) UnregisterEventHotKey(ref);
    }
    [_refs removeAllObjects];
    [_handlers removeAllObjects];
}

@end
