#import <Foundation/Foundation.h>
#include <stdbool.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// YES when the private MRNowPlayingRequest class is available.
FOUNDATION_EXPORT bool ScreenStayNowPlayingRequestAvailable(void);

/// Playback state through MRNowPlayingRequest. This path is not blocked by
/// the entitlement check that affects the old MediaRemote C functions on
/// macOS 15.4 and newer.
FOUNDATION_EXPORT bool ScreenStayNowPlayingIsPlaying(void);
FOUNDATION_EXPORT uint32_t ScreenStayNowPlayingPlaybackState(void);

/// Instance request API. Unlike the class properties above, these go through
/// the active player path and work on current macOS releases.
FOUNDATION_EXPORT uint32_t ScreenStayNowPlayingRequestPlaybackState(void);
FOUNDATION_EXPORT bool ScreenStayNowPlayingRequestIsPlaying(void);
FOUNDATION_EXPORT float ScreenStayNowPlayingRequestPlaybackRate(void);

/// Localized name and bundle identifier of the app that owns the current
/// Now Playing session, or nil when there is no session.
FOUNDATION_EXPORT NSString * _Nullable ScreenStayNowPlayingApplicationName(void);
FOUNDATION_EXPORT NSString * _Nullable ScreenStayNowPlayingBundleIdentifier(void);

NS_ASSUME_NONNULL_END
