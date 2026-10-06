#import "NVPlayer.h"
#import "NVClient.h"
#import "NVDownloadManager.h"
#import "NVTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface NVPlayer ()
@property (nonatomic, strong) NSArray *queue;
@property (nonatomic, strong) NSArray *originalQueue;
@property (nonatomic) NSInteger index;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *observedItem;
@property (nonatomic) BOOL playing, resumeAfterInterruption;
@property (nonatomic) int failCount;
@end

@implementation NVPlayer

+ (instancetype)shared {
    static NVPlayer *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[NVPlayer alloc] init]; });
    return p;
}

- (id)init {
    self = [super init];
    if (self) {
        _queue = @[]; _originalQueue = @[]; _index = -1;
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(itemDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
        [nc addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];
        [nc addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    }
    return self;
}

#pragma mark State

- (NSDictionary *)currentSong {
    return (self.index >= 0 && self.index < (NSInteger)self.queue.count) ? self.queue[self.index] : nil;
}
- (BOOL)isPlaying { return self.playing; }

- (NSTimeInterval)currentTime {
    if (!self.player.currentItem) return 0;
    NSTimeInterval t = CMTimeGetSeconds(self.player.currentTime);
    return isnan(t) ? 0 : t;
}
- (NSTimeInterval)duration {
    NSTimeInterval d = [self.currentSong[@"duration"] doubleValue];
    if (d > 0) return d;
    d = CMTimeGetSeconds(self.player.currentItem.duration);
    return (isnan(d) || isinf(d)) ? 0 : d;
}

- (void)post { [[NSNotificationCenter defaultCenter] postNotificationName:NVPlayerChangedNotification object:nil]; }

#pragma mark Playback

- (void)playSongs:(NSArray *)songs startIndex:(NSInteger)i { [self playSongs:songs startIndex:i shuffled:NO]; }

- (void)playSongs:(NSArray *)songs startIndex:(NSInteger)i shuffled:(BOOL)shuffled {
    if (!songs.count) return;
    self.originalQueue = [songs copy];
    self.queue = self.originalQueue;
    _shuffle = NO;
    self.index = shuffled ? (NSInteger)arc4random_uniform((u_int32_t)songs.count) : MAX(0, MIN(i, (NSInteger)songs.count - 1));
    if (shuffled) self.shuffle = YES;      // moves the chosen song to the front, shuffles the rest
    self.failCount = 0;
    [self startIndex:self.index];
}

- (void)startIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.queue.count) return;
    self.index = i;
    NSDictionary *song = self.queue[i];
    NSURL *url = [[NVDownloadManager shared] localURLForSongID:song[@"id"]] ?: [[NVClient shared] streamURLForSong:song];
    if (!url) { [self pause]; return; }

    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [self detachItem];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    [item addObserver:self forKeyPath:@"status" options:0 context:NULL];
    self.observedItem = item;
    if (!self.player) self.player = [[AVPlayer alloc] initWithPlayerItem:item];
    else [self.player replaceCurrentItemWithPlayerItem:item];
    [self.player play];
    self.playing = YES;
    [self publishNowPlaying];
    [self post];
    [[NVClient shared] scrobbleSongID:song[@"id"] submission:NO];
}

- (void)detachItem {
    if (self.observedItem) {
        @try { [self.observedItem removeObserver:self forKeyPath:@"status"]; } @catch (NSException *e) {}
        self.observedItem = nil;
    }
}

- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)obj change:(NSDictionary *)ch context:(void *)ctx {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (obj != self.observedItem) return;
        AVPlayerItem *it = obj;
        if (it.status == AVPlayerItemStatusFailed) {
            if (++self.failCount < 3) [self advance:YES]; else { self.failCount = 0; [self pause]; }
        } else if (it.status == AVPlayerItemStatusReadyToPlay) {
            self.failCount = 0;
            [self publishNowPlaying];
        }
    });
}

- (void)itemDidEnd:(NSNotification *)n {
    if (n.object != self.observedItem) return;
    [[NVClient shared] scrobbleSongID:self.currentSong[@"id"] submission:YES];
    [self advance:YES];
}

- (void)advance:(BOOL)automatic {
    if (automatic && self.repeatMode == 2) { [self startIndex:self.index]; return; }
    NSInteger n = self.index + 1;
    if (n < (NSInteger)self.queue.count) [self startIndex:n];
    else if (self.repeatMode == 1 && self.queue.count) [self startIndex:0];
    else if (automatic) {
        [self.player pause];
        [self.player seekToTime:kCMTimeZero];
        self.playing = NO;
        [self publishNowPlaying];
        [self post];
    }
}

- (void)next { [self advance:NO]; }

- (void)previous {
    if (self.currentTime > 3 || self.index <= 0) [self seekToTime:0];
    else [self startIndex:self.index - 1];
}

- (void)play {
    if (!self.player.currentItem) { if (self.queue.count) [self startIndex:MAX(self.index, 0)]; return; }
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [self.player play]; self.playing = YES;
    [self publishNowPlaying]; [self post];
}
- (void)pause { [self.player pause]; self.playing = NO; [self publishNowPlaying]; [self post]; }
- (void)togglePlayPause { self.playing ? [self pause] : [self play]; }

- (void)seekToTime:(NSTimeInterval)t {
    [self.player seekToTime:CMTimeMakeWithSeconds(MAX(t, 0), 600)];
    [self publishNowPlaying];
}

#pragma mark Queue

- (void)setShuffle:(BOOL)on {
    if (_shuffle == on) return;
    _shuffle = on;
    NSDictionary *cur = self.currentSong;
    if (cur) {
        if (on) {
            NSMutableArray *rest = [self.queue mutableCopy];
            [rest removeObjectAtIndex:self.index];
            for (NSInteger i = (NSInteger)rest.count - 1; i > 0; i--)
                [rest exchangeObjectAtIndex:i withObjectAtIndex:arc4random_uniform((u_int32_t)(i + 1))];
            self.queue = [@[cur] arrayByAddingObjectsFromArray:rest];
            self.index = 0;
        } else {
            self.queue = self.originalQueue;
            NSUInteger i = [self.queue indexOfObject:cur];
            self.index = (i == NSNotFound) ? 0 : (NSInteger)i;
        }
    }
    [self post];
}

- (void)setRepeatMode:(NSInteger)m { _repeatMode = m; [self post]; }

- (void)addNext:(NSDictionary *)song {
    if (!self.queue.count) { [self playSongs:@[song] startIndex:0]; return; }
    NSMutableArray *q = [self.queue mutableCopy];
    [q insertObject:song atIndex:self.index + 1];
    self.queue = q;
    NSMutableArray *o = [self.originalQueue mutableCopy]; [o addObject:song]; self.originalQueue = o;
    [self post];
}
- (void)addToQueue:(NSDictionary *)song {
    if (!self.queue.count) { [self playSongs:@[song] startIndex:0]; return; }
    self.queue = [self.queue arrayByAddingObject:song];
    self.originalQueue = [self.originalQueue arrayByAddingObject:song];
    [self post];
}

- (void)jumpToIndex:(NSInteger)i { [self startIndex:i]; }

- (void)removeQueueIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.queue.count) return;
    NSDictionary *song = self.queue[i];
    NSMutableArray *q = [self.queue mutableCopy]; [q removeObjectAtIndex:i]; self.queue = q;
    NSMutableArray *o = [self.originalQueue mutableCopy];
    NSUInteger oi = [o indexOfObject:song];
    if (oi != NSNotFound) [o removeObjectAtIndex:oi];
    self.originalQueue = o;
    if (i < self.index) {
        self.index--;
    } else if (i == self.index) {
        if (q.count) {
            [self startIndex:MIN(i, (NSInteger)q.count - 1)];
        } else {
            [self detachItem];
            [self.player pause];
            [self.player replaceCurrentItemWithPlayerItem:nil];
            self.playing = NO; self.index = -1;
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        }
    }
    [self post];
}

#pragma mark System integration

- (void)publishNowPlaying {
    NSDictionary *song = self.currentSong;
    if (!song) { [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil; return; }
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[MPMediaItemPropertyTitle] = song[@"title"] ?: @"";
    if (song[@"artist"]) d[MPMediaItemPropertyArtist] = song[@"artist"];
    if (song[@"album"])  d[MPMediaItemPropertyAlbumTitle] = song[@"album"];
    d[MPMediaItemPropertyPlaybackDuration] = @(self.duration);
    d[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.currentTime);
    d[MPNowPlayingInfoPropertyPlaybackRate] = @(self.playing ? 1.0 : 0.0);
    NSDictionary *old = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
    if (old[MPMediaItemPropertyArtwork] && [old[MPMediaItemPropertyTitle] isEqual:d[MPMediaItemPropertyTitle]])
        d[MPMediaItemPropertyArtwork] = old[MPMediaItemPropertyArtwork];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = d;

    NSString *cid = song[@"coverArt"];
    if (cid && !d[MPMediaItemPropertyArtwork]) {
        [NVImageLoader loadCover:cid size:300 completion:^(UIImage *img) {
            if (!img || ![self.currentSong[@"id"] isEqual:song[@"id"]]) return;
            NSMutableDictionary *n = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
            if (!n) return;
            n[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:img];
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = n;
        }];
    }
}

- (void)handleRemoteEvent:(UIEvent *)event {
    if (event.type != UIEventTypeRemoteControl) return;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlPlay:           [self play]; break;
        case UIEventSubtypeRemoteControlPause:          [self pause]; break;
        case UIEventSubtypeRemoteControlTogglePlayPause: [self togglePlayPause]; break;
        case UIEventSubtypeRemoteControlNextTrack:      [self next]; break;
        case UIEventSubtypeRemoteControlPreviousTrack:  [self previous]; break;
        default: break;
    }
}

- (void)interruption:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        self.resumeAfterInterruption = self.playing;
        [self pause];
    } else {
        NSUInteger opts = [n.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if (self.resumeAfterInterruption && (opts & AVAudioSessionInterruptionOptionShouldResume)) [self play];
        self.resumeAfterInterruption = NO;
    }
}

- (void)routeChanged:(NSNotification *)n {   // headphones unplugged -> pause, like the stock Music app
    NSUInteger reason = [n.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable && self.playing) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self pause]; });
    }
}

@end
