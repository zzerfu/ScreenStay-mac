#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#include <stdio.h>

// Loaded into /usr/bin/perl, which is permitted to use MediaRemote on macOS
// 15.4 and newer. The result is printed to stdout: 1 playing, 0 not playing,
// -1 unavailable/timed out.
void screenstay_now_playing_is_playing(void) {
    static dispatch_once_t once;
    static void *framework;
    dispatch_once(&once, ^{
        framework = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        );
    });

    if (!framework) {
        printf("-1\n");
        fflush(stdout);
        return;
    }

    typedef void (*Function)(dispatch_queue_t, void (^)(Boolean));
    Function function = (Function)dlsym(
        framework,
        "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
    );
    if (!function) {
        printf("-1\n");
        fflush(stdout);
        return;
    }

    __block int result = -1;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    function(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(Boolean playing) {
        result = playing ? 1 : 0;
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)
    );

    printf("%d\n", result);
    fflush(stdout);
}
