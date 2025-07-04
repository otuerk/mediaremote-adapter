/*
 * Media remote framework header.
 *
 * Copyright (c) 2013-2014 Cykey (David Murray)
 * All rights reserved.
 */

#ifndef MEDIAREMOTE_H_
#define MEDIAREMOTE_H_

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <objc/objc.h>

#if __cplusplus
extern "C" {
#endif

#pragma mark - Notifications
extern CFStringRef kMRMediaRemoteNowPlayingInfoDidChangeNotification;
extern CFStringRef kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification;
extern CFStringRef kMRMediaRemotePickableRoutesDidChangeNotification;
extern CFStringRef kMRMediaRemoteNowPlayingApplicationDidChangeNotification;
extern CFStringRef kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification;
extern CFStringRef kMRMediaRemoteRouteStatusDidChangeNotification;

#pragma mark - Keys
extern CFStringRef kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey;
extern CFStringRef kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey;
extern CFStringRef kMRMediaRemoteNowPlayingInfoAlbum;
extern CFStringRef kMRMediaRemoteNowPlayingInfoArtist;
extern CFStringRef kMRMediaRemoteNowPlayingInfoArtworkData;
extern CFStringRef kMRMediaRemoteNowPlayingInfoArtworkMIMEType;
extern CFStringRef kMRMediaRemoteNowPlayingInfoChapterNumber;
extern CFStringRef kMRMediaRemoteNowPlayingInfoComposer;
extern CFStringRef kMRMediaRemoteNowPlayingInfoDuration;
extern CFStringRef kMRMediaRemoteNowPlayingInfoElapsedTime;
extern CFStringRef kMRMediaRemoteNowPlayingInfoGenre;
extern CFStringRef kMRMediaRemoteNowPlayingInfoIsAdvertisement;
extern CFStringRef kMRMediaRemoteNowPlayingInfoIsBanned;
extern CFStringRef kMRMediaRemoteNowPlayingInfoIsInWishList;
extern CFStringRef kMRMediaRemoteNowPlayingInfoIsLiked;
extern CFStringRef kMRMediaRemoteNowPlayingInfoIsMusicApp;
extern CFStringRef kMRMediaRemoteNowPlayingInfoMediaType;
extern CFStringRef kMRMediaRemoteNowPlayingInfoPlaybackRate;
extern CFStringRef kMRMediaRemoteNowPlayingInfoProhibitsSkip;
extern CFStringRef kMRMediaRemoteNowPlayingInfoQueueIndex;
extern CFStringRef kMRMediaRemoteNowPlayingInfoRadioStationIdentifier;
extern CFStringRef kMRMediaRemoteNowPlayingInfoRepeatMode;
extern CFStringRef kMRMediaRemoteNowPlayingInfoShuffleMode;
extern CFStringRef kMRMediaRemoteNowPlayingInfoStartTime;
extern CFStringRef kMRMediaRemoteNowPlayingInfoSupportsFastForward15Seconds;
extern CFStringRef kMRMediaRemoteNowPlayingInfoSupportsIsBanned;
extern CFStringRef kMRMediaRemoteNowPlayingInfoSupportsIsLiked;
extern CFStringRef kMRMediaRemoteNowPlayingInfoSupportsRewind15Seconds;
extern CFStringRef kMRMediaRemoteNowPlayingInfoTimestamp;
extern CFStringRef kMRMediaRemoteNowPlayingInfoTitle;
extern CFStringRef kMRMediaRemoteNowPlayingInfoTotalChapterCount;
extern CFStringRef kMRMediaRemoteNowPlayingInfoTotalDiscCount;
extern CFStringRef kMRMediaRemoteNowPlayingInfoTotalQueueCount;
extern CFStringRef kMRMediaRemoteNowPlayingInfoTotalTrackCount;
extern CFStringRef kMRMediaRemoteNowPlayingInfoTrackNumber;
extern CFStringRef kMRMediaRemoteNowPlayingInfoUniqueIdentifier;
extern CFStringRef kMRMediaRemoteNowPlayingInfoRadioStationHash;
extern CFStringRef kMRMediaRemoteOptionMediaType;
extern CFStringRef kMRMediaRemoteOptionSourceID;
extern CFStringRef kMRMediaRemoteOptionTrackID;
extern CFStringRef kMRMediaRemoteOptionStationID;
extern CFStringRef kMRMediaRemoteOptionStationHash;
extern CFStringRef kMRMediaRemoteRouteDescriptionUserInfoKey;
extern CFStringRef kMRMediaRemoteRouteStatusUserInfoKey;

#pragma mark - API
typedef enum {
    kMRPlay = 0,
    kMRPause = 1,
    kMRTogglePlayPause = 2,
    kMRStop = 3,
    kMRNextTrack = 4,
    kMRPreviousTrack = 5,
    kMRToggleShuffle = 6,
    kMRToggleRepeat = 7,
    kMRStartForwardSeek = 8,
    kMREndForwardSeek = 9,
    kMRStartBackwardSeek = 10,
    kMREndBackwardSeek = 11,
    kMRGoBackFifteenSeconds = 12,
    kMRSkipFifteenSeconds = 13,
    kMRLikeTrack = 0x6A,
    kMRBanTrack = 0x6B,
    kMRAddTrackToWishList = 0x6C,
    kMRRemoveTrackFromWishList = 0x6D
} MRCommand;

Boolean MRMediaRemoteSendCommand(MRCommand command, id userInfo);
void MRMediaRemoteSetElapsedTime(double elapsedTime);
void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t queue);
void MRMediaRemoteUnregisterForNowPlayingNotifications();

typedef void (^MRMediaRemoteGetNowPlayingInfoCompletion)(CFDictionaryRef information);
typedef void (^MRMediaRemoteGetNowPlayingApplicationPIDCompletion)(int PID);
typedef void (^MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion)(Boolean isPlaying);

void MRMediaRemoteGetNowPlayingApplicationPID(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion completion);
void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingInfoCompletion completion);
void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion completion);

#if __cplusplus
}
#endif

#endif /* MEDIAREMOTE_H_ */