#import "NowPlayingBridge.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>

// macOS 15.4 moved Now Playing behind an entitlement check for the old C API.
// MRNowPlayingRequest is still usable and is the path used by control-center
// and menu-bar utilities. Everything is read-only here.
static Class ScreenStayNowPlayingRequestClass(void) {
    static Class requestClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleWithPath:
            @"/System/Library/PrivateFrameworks/MediaRemote.framework"];
        [bundle load];
        requestClass = NSClassFromString(@"MRNowPlayingRequest");
    });
    return requestClass;
}

bool ScreenStayNowPlayingRequestAvailable(void) {
    return ScreenStayNowPlayingRequestClass() != Nil;
}

static BOOL ScreenStayCallBool(Class cls, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![cls respondsToSelector:selector]) {
        return NO;
    }
    BOOL (*function)(id, SEL) = (BOOL (*)(id, SEL))[cls methodForSelector:selector];
    return function ? function((id)cls, selector) : NO;
}

static uint32_t ScreenStayCallUInt32(Class cls, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![cls respondsToSelector:selector]) {
        return 0;
    }
    uint32_t (*function)(id, SEL) = (uint32_t (*)(id, SEL))[cls methodForSelector:selector];
    return function ? function((id)cls, selector) : 0;
}

uint32_t ScreenStayNowPlayingPlaybackState(void) {
    Class cls = ScreenStayNowPlayingRequestClass();
    if (!cls) {
        return 0;
    }
    return ScreenStayCallUInt32(cls, @"localPlaybackState");
}

bool ScreenStayNowPlayingIsPlaying(void) {
    Class cls = ScreenStayNowPlayingRequestClass();
    if (!cls) {
        return false;
    }

    if (ScreenStayCallBool(cls, @"localIsPlaying")) {
        return true;
    }

    // kMRPlaybackStatePlaying == 1.
    return ScreenStayNowPlayingPlaybackState() == 1;
}

NSString * _Nullable ScreenStayNowPlayingApplicationName(void) {
    Class cls = ScreenStayNowPlayingRequestClass();
    if (!cls) {
        return nil;
    }

    SEL pathSelector = NSSelectorFromString(@"localNowPlayingPlayerPath");
    if (![cls respondsToSelector:pathSelector]) {
        return nil;
    }

    id (*objectMessage)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id playerPath = objectMessage((id)cls, pathSelector);
    if (!playerPath) {
        return nil;
    }

    SEL clientSelector = NSSelectorFromString(@"client");
    if (![playerPath respondsToSelector:clientSelector]) {
        return nil;
    }
    id client = objectMessage(playerPath, clientSelector);
    if (!client) {
        return nil;
    }

    SEL displayNameSelector = NSSelectorFromString(@"displayName");
    if (![client respondsToSelector:displayNameSelector]) {
        return nil;
    }
    id displayName = objectMessage(client, displayNameSelector);
    if ([displayName isKindOfClass:[NSString class]]) {
        return (NSString *)displayName;
    }
    return nil;
}

NSString * _Nullable ScreenStayNowPlayingBundleIdentifier(void) {
    Class cls = ScreenStayNowPlayingRequestClass();
    if (!cls) {
        return nil;
    }

    SEL pathSelector = NSSelectorFromString(@"localNowPlayingPlayerPath");
    if (![cls respondsToSelector:pathSelector]) {
        return nil;
    }

    id (*objectMessage)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id playerPath = objectMessage((id)cls, pathSelector);
    if (!playerPath) {
        return nil;
    }

    SEL clientSelector = NSSelectorFromString(@"client");
    if (![playerPath respondsToSelector:clientSelector]) {
        return nil;
    }
    id client = objectMessage(playerPath, clientSelector);
    if (!client) {
        return nil;
    }

    SEL bundleSelector = NSSelectorFromString(@"bundleIdentifier");
    if (![client respondsToSelector:bundleSelector]) {
        return nil;
    }
    id bundleIdentifier = objectMessage(client, bundleSelector);
    if ([bundleIdentifier isKindOfClass:[NSString class]]) {
        return (NSString *)bundleIdentifier;
    }
    return nil;
}

#pragma mark - Instance request API

static id ScreenStayNowPlayingRequestWithLocalPath(void) {
    Class cls = ScreenStayNowPlayingRequestClass();
    if (!cls) {
        return nil;
    }

    SEL pathSelector = NSSelectorFromString(@"localNowPlayingPlayerPath");
    if (![cls respondsToSelector:pathSelector]) {
        return nil;
    }

    id (*objectMessage)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id playerPath = objectMessage((id)cls, pathSelector);
    if (!playerPath) {
        return nil;
    }

    id allocated = objectMessage((id)cls, NSSelectorFromString(@"alloc"));
    SEL initSelector = NSSelectorFromString(@"initWithPlayerPath:");
    id (*initMessage)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
    return initMessage(allocated, initSelector, playerPath);
}

uint32_t ScreenStayNowPlayingRequestPlaybackState(void) {
    id request = ScreenStayNowPlayingRequestWithLocalPath();
    if (!request) {
        return 0;
    }

    SEL selector = NSSelectorFromString(@"requestPlaybackStateOnQueue:completion:");
    if (![request respondsToSelector:selector]) {
        return 0;
    }

    typedef void (^Completion)(uint32_t);
    typedef void (*RequestFunction)(id, SEL, dispatch_queue_t, Completion);
    RequestFunction function = (RequestFunction)[request methodForSelector:selector];
    if (!function) {
        return 0;
    }

    __block uint32_t state = 0;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    function(request, selector, queue, ^(uint32_t value) {
        state = value;
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)
    );
    return state;
}

bool ScreenStayNowPlayingRequestIsPlaying(void) {
    id request = ScreenStayNowPlayingRequestWithLocalPath();
    if (!request) {
        return false;
    }

    SEL selector = NSSelectorFromString(@"requestIsPlayingOnQueue:completion:");
    if (![request respondsToSelector:selector]) {
        return false;
    }

    typedef void (^Completion)(BOOL);
    typedef void (*RequestFunction)(id, SEL, dispatch_queue_t, Completion);
    RequestFunction function = (RequestFunction)[request methodForSelector:selector];
    if (!function) {
        return false;
    }

    __block BOOL isPlaying = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    function(request, selector, queue, ^(BOOL value) {
        isPlaying = value;
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)
    );
    return isPlaying;
}

float ScreenStayNowPlayingRequestPlaybackRate(void) {
    id request = ScreenStayNowPlayingRequestWithLocalPath();
    if (!request) {
        return 0.0f;
    }

    SEL selector = NSSelectorFromString(@"requestPlaybackRateOnQueue:completion:");
    if (![request respondsToSelector:selector]) {
        return 0.0f;
    }

    typedef void (^Completion)(float);
    typedef void (*RequestFunction)(id, SEL, dispatch_queue_t, Completion);
    RequestFunction function = (RequestFunction)[request methodForSelector:selector];
    if (!function) {
        return 0.0f;
    }

    __block float rate = 0.0f;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    function(request, selector, queue, ^(float value) {
        rate = value;
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)
    );
    return rate;
}
