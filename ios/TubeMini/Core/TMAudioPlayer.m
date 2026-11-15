#import "TMAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "TMAPIClient.h"
#import "TMLibrary.h"
#import "TMLog.h"

NSString *const TMAudioPlayerDidChangeNotification = @"TMAudioPlayerDidChange";

static const NSTimeInterval kSaveEvery = 15;
static void *kStatusContext = &kStatusContext;

@implementation TMAudioPlayer {
    AVPlayer *_player;
    AVPlayerItem *_item;
    id _timeObserver;
    NSInteger _startAt;
    NSTimeInterval _lastSave;
    BOOL _retried;
    UIImage *_artwork;
}

+ (instancetype)shared {
    static TMAudioPlayer *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[TMAudioPlayer alloc] init]; });
    return p;
}

- (instancetype)init {
    if ((self = [super init])) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(save)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

- (BOOL)active {
    return _player != nil;
}

- (BOOL)playing {
    return _player.rate > 0;
}

- (NSTimeInterval)position {
    NSTimeInterval t = CMTimeGetSeconds(_player.currentTime);
    return isfinite(t) && t > 0 ? t : 0;
}

- (NSTimeInterval)duration {
    NSTimeInterval d = _item ? CMTimeGetSeconds(_item.duration) : 0;
    return isfinite(d) && d > 0 ? d : _video.duration;
}

- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:TMAudioPlayerDidChangeNotification object:self];
}

#pragma mark - Loading

- (void)playURL:(NSString *)url video:(TMVideo *)video startAt:(NSInteger)seconds {
    if (_player) [self stop];
    _video = video;
    _startAt = MAX(seconds, 0);
    _retried = NO;
    _lastSave = 0;
    [self load:url];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self loadArtwork];
    TMLog(@"[audio] %@ từ %ld giây", video.videoID, (long)_startAt);
}

- (void)load:(NSString *)url {
    [self unloadItem];
    _item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:url]];
    [_item addObserver:self forKeyPath:@"status" options:0 context:kStatusContext];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ended:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:_item];
    if (!_player) {
        _player = [AVPlayer playerWithPlayerItem:_item];
        __weak TMAudioPlayer *weakSelf = self;
        _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2)
                                                              queue:dispatch_get_main_queue()
                                                         usingBlock:^(CMTime time) { [weakSelf tick]; }];
    } else {
        [_player replaceCurrentItemWithPlayerItem:_item];
    }
    [self changed];
}

- (void)unloadItem {
    if (!_item) return;
    [_item removeObserver:self forKeyPath:@"status" context:kStatusContext];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    _item = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (object != self->_item) return;
        if (self->_item.status == AVPlayerItemStatusReadyToPlay) {
            if (self->_startAt > 0) [self->_player seekToTime:CMTimeMakeWithSeconds(self->_startAt, 1)];
            self->_startAt = 0;
            [self->_player play];
            [self changed];
            [self updateNowPlaying];
        } else if (self->_item.status == AVPlayerItemStatusFailed) {
            [self failed:self->_item.error];
        }
    });
}

/// Refused / expired link: one fresh link from the server, from the same position.
- (void)failed:(NSError *)error {
    TMLog(@"[audio] lỗi %@: %@", _video.videoID, error.localizedDescription);
    if (_retried) {
        [self stop];
        [[[UIAlertView alloc] initWithTitle:@"Không phát được"
                                    message:@"Không nghe được video này. Thử lại sau."
                                   delegate:nil
                          cancelButtonTitle:@"Đóng"
                          otherButtonTitles:nil] show];
        return;
    }
    _retried = YES;
    _startAt = (NSInteger)self.position;
    NSString *vid = _video.videoID;
    [[TMAPIClient shared] streams:vid
                            fresh:YES
                       completion:^(TMStreamSet *set, NSString *err) {
                           if (![self->_video.videoID isEqualToString:vid]) return;
                           if (set.audioURL.length) {
                               [self load:set.audioURL];
                           } else {
                               [self failed:nil];
                           }
                       }];
}

- (void)ended:(NSNotification *)n {
    [self store:(NSInteger)self.duration];
    [self stop];
}

#pragma mark - Controls

- (void)togglePlay {
    if (!_player) return;
    if (self.playing) {
        [_player pause];
        [self save];
    } else {
        [_player play];
    }
    [self changed];
    [self updateNowPlaying];
}

- (void)seekTo:(NSTimeInterval)seconds {
    if (!_player) return;
    NSTimeInterval d = self.duration;
    seconds = MAX(0, d > 0 ? MIN(seconds, d - 1) : seconds);
    [_player seekToTime:CMTimeMakeWithSeconds(seconds, 1)];
    [self changed];
    [self updateNowPlaying];
}

- (void)skip:(NSTimeInterval)delta {
    [self seekTo:self.position + delta];
}

- (void)stop {
    if (!_player) return;
    [self save];
    [_player pause];
    if (_timeObserver) [_player removeTimeObserver:_timeObserver];
    _timeObserver = nil;
    [self unloadItem];
    _player = nil;
    _video = nil;
    _artwork = nil;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    TMLog(@"[audio] dừng");
    [self changed];
}

- (void)remoteControl:(UIEvent *)event {
    if (!_player || event.type != UIEventTypeRemoteControl) return;
    switch (event.subtype) {
    case UIEventSubtypeRemoteControlTogglePlayPause: [self togglePlay]; break;
    case UIEventSubtypeRemoteControlPlay:
        if (!self.playing) [self togglePlay];
        break;
    case UIEventSubtypeRemoteControlPause:
    case UIEventSubtypeRemoteControlStop:
        if (self.playing) [self togglePlay];
        break;
    // iOS 6 lock screen has no scrubber: ⏮ / ⏭ jump instead
    case UIEventSubtypeRemoteControlNextTrack: [self skip:15]; break;
    case UIEventSubtypeRemoteControlPreviousTrack: [self skip:-15]; break;
    default: return;
    }
    TMLog(@"[audio] điều khiển từ xa: %ld", (long)event.subtype);
}

#pragma mark - Position, lock screen

- (void)tick {
    [self changed];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (self.playing && now - _lastSave >= kSaveEvery) {
        _lastSave = now;
        [self save];
    }
}

- (void)save {
    if (_player && _video) [self store:(NSInteger)self.position];
}

- (void)store:(NSInteger)position {
    NSInteger duration = (NSInteger)self.duration;
    [[TMAPIClient shared] savePosition:position duration:duration video:_video];
    [[TMLibrary shared] historyChangedForVideo:_video.videoID position:position duration:duration];
    [self updateNowPlaying];
}

- (void)loadArtwork {
    NSString *vid = _video.videoID;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", vid]];
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url]
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *r, NSData *data, NSError *e) {
                               UIImage *img = data ? [UIImage imageWithData:data] : nil;
                               if (!img || ![self->_video.videoID isEqualToString:vid]) return;
                               self->_artwork = img;
                               [self updateNowPlaying];
                           }];
}

- (void)updateNowPlaying {
    if (!_player || !_video) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = _video.title ?: @"";
    info[MPMediaItemPropertyArtist] = _video.author ?: @"TubeMini";
    if (self.duration > 0) info[MPMediaItemPropertyPlaybackDuration] = @(self.duration);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.position);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.playing ? 1.0 : 0.0);
    if (_artwork) info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:_artwork];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

@end
