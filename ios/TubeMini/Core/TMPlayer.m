#import "TMPlayer.h"
#import "TMAPIClient.h"
#import "TMAudioPlayer.h"
#import "TMImageLoader.h"
#import "TMLocalServer.h"
#import "TMLibrary.h"
#import "TMLog.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface TMPlayer ()
@property (nonatomic, readwrite, copy) NSString *playingLabel;
@end

@implementation TMPlayer {
    TMVideo *_video;
    NSInteger _quality;
    __weak UIViewController *_presenter;
    MPMoviePlayerViewController *_playerVC;
    TMStreamSet *_streams;
    TMStream *_stream;
    BOOL _retried;
    UIView *_hud;
    UILabel *_hudLabel;
    NSTimer *_countdown;
    NSInteger _remaining;
    NSInteger _generation; // cancels callbacks of a playback the user already left
    NSInteger _startAt;
    NSTimer *_saveTimer;
    NSInteger _lastPosition, _lastDuration; // last known from the player (seconds)
    BOOL _audioOnly;
    // Sound in the background: playing when the app started to leave the screen, not paused by the user since
    BOOL _keepSound;
    NSTimer *_guard;              // plays again whenever iOS pauses the movie, until _guardUntil
    NSTimeInterval _guardUntil;
    NSInteger _resumes;
    UIBackgroundTaskIdentifier _bgTask; // keeps the app running meanwhile
    NSString *_localPath;  // playing a downloaded file
    UIImage *_artwork;     // lock screen picture (the video thumbnail)
}

static const NSTimeInterval kSaveInterval = 15;

+ (instancetype)shared {
    static TMPlayer *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[TMPlayer alloc] init]; });
    return p;
}

- (instancetype)init {
    if ((self = [super init])) {
        _bgTask = UIBackgroundTaskInvalid;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(willResignActive) name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [nc addObserver:self selector:@selector(didBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        [nc addObserver:self
               selector:@selector(audioInterrupted:)
                   name:AVAudioSessionInterruptionNotification
                 object:[AVAudioSession sharedInstance]];
        [nc addObserver:self
               selector:@selector(playbackStateChanged:)
                   name:MPMoviePlayerPlaybackStateDidChangeNotification
                 object:nil];
    }
    return self;
}

- (MPMoviePlayerController *)moviePlayer {
    return _playerVC.moviePlayer;
}

#pragma mark - HUD

- (void)showHUD:(NSString *)text on:(UIView *)host {
    if (!_hud) {
        _hud = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
        _hud.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
        _hud.layer.cornerRadius = 12;
        _hud.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        UIActivityIndicatorView *spin =
            [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        spin.center = CGPointMake(160, 38);
        [spin startAnimating];
        [_hud addSubview:spin];
        _hudLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 64, 296, 48)];
        _hudLabel.numberOfLines = 2;
        _hudLabel.textAlignment = NSTextAlignmentCenter;
        _hudLabel.textColor = [UIColor whiteColor];
        _hudLabel.backgroundColor = [UIColor clearColor];
        _hudLabel.font = [UIFont systemFontOfSize:16];
        [_hud addSubview:_hudLabel];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancel)];
        [_hud addGestureRecognizer:tap];
    }
    _hudLabel.text = text;
    if (host && _hud.superview != host) {
        [_hud removeFromSuperview];
        _hud.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
        [host addSubview:_hud];
    }
}

/// View that rotates with the interface. On iOS 6 views added straight to the UIWindow stay in
/// portrait (only the root view controller's view is rotated), so the HUD goes on that view.
- (UIView *)hostFor:(UIViewController *)presenter {
    UIView *root = presenter.view.window.rootViewController.view;
    return root ?: presenter.view;
}

- (void)hideHUD {
    [_countdown invalidate];
    _countdown = nil;
    [_hud removeFromSuperview];
}

/// Tapping the HUD abandons the pending playback.
- (void)cancel {
    _generation++;
    [self hideHUD];
}

- (void)alert:(NSString *)message {
    [[[UIAlertView alloc] initWithTitle:@"Không phát được" message:message delegate:nil cancelButtonTitle:@"Đóng"
                      otherButtonTitles:nil] show];
}

#pragma mark - Flow

- (void)playVideo:(TMVideo *)video quality:(NSInteger)quality from:(UIViewController *)presenter {
    [self playVideo:video quality:quality startAt:0 from:presenter];
}

- (void)playVideo:(TMVideo *)video quality:(NSInteger)quality startAt:(NSInteger)seconds from:(UIViewController *)presenter {
    _audioOnly = NO;
    _localPath = nil;
    [self begin:video quality:quality startAt:seconds from:presenter];
}

- (void)playAudioOf:(TMVideo *)video startAt:(NSInteger)seconds from:(UIViewController *)presenter {
    _audioOnly = YES;
    _localPath = nil;
    [self begin:video quality:360 startAt:seconds from:presenter];
}

- (void)playFile:(NSString *)path video:(TMVideo *)video startAt:(NSInteger)seconds from:(UIViewController *)presenter {
    [[TMAudioPlayer shared] stop];
    _generation++;
    _audioOnly = NO;
    _localPath = [path copy];
    _video = video;
    _presenter = presenter;
    _retried = YES; // nothing to refetch
    _startAt = MAX(seconds, 0);
    _lastPosition = _startAt;
    _lastDuration = video.duration;
    _streams = nil;
    TMStream *s = [[TMStream alloc] init];
    s.kind = @"file";
    s.quality = 360;
    // HLS can't be played from a file:// URL on iOS 6: serve the folder over HTTP on 127.0.0.1
    NSURL *url = [path hasSuffix:@".m3u8"] ? [[TMLocalServer shared] urlForFile:path] : [NSURL fileURLWithPath:path];
    s.url = url.absoluteString;
    _stream = s;
    [self startPlayback];
}

- (void)begin:(TMVideo *)video quality:(NSInteger)quality startAt:(NSInteger)seconds from:(UIViewController *)presenter {
    [[TMAudioPlayer shared] stop]; // one sound at a time
    _generation++;
    _video = video;
    _quality = quality;
    _presenter = presenter;
    _retried = NO;
    _startAt = MAX(seconds, 0);
    _lastPosition = _startAt;
    _lastDuration = video.duration;
    [self showHUD:@"Đang lấy link phát…\n(có thể mất 5–10 giây)" on:[self hostFor:presenter]];
    [self fetchStreams:NO];
}

- (void)fetchStreams:(BOOL)fresh {
    NSInteger gen = _generation;
    [[TMAPIClient shared] streams:_video.videoID
                            fresh:fresh
                       completion:^(TMStreamSet *set, NSString *error) {
                           if (gen != self->_generation) return;
                           if (error) {
                               [self hideHUD];
                               [self dismissPlayer];
                               [self alert:error];
                               return;
                           }
                           self->_streams = set;
                           self->_stream = [set streamForQuality:self->_quality];
                           if (self->_audioOnly && set.audioURL.length) {
                               TMStream *audio = [[TMStream alloc] init];
                               audio.kind = @"audio";
                               audio.url = set.audioURL;
                               self->_stream = audio;
                           }
                           [self waitThenPlay:set.availableIn];
                       }];
}

- (void)waitThenPlay:(NSInteger)seconds {
    if (seconds <= 0) {
        [self hideHUD];
        [self startPlayback];
        return;
    }
    _remaining = seconds;
    [self tick];
    _countdown = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)tick {
    if (_remaining <= 0) {
        [self hideHUD];
        [self startPlayback];
        return;
    }
    // Shown on top of the player too when this is a retry
    UIView *host = _playerVC ? _playerVC.view : [self hostFor:_presenter];
    [self showHUD:[NSString stringWithFormat:@"Video có quảng cáo: YouTube cho phát sau %ld giây…\n(chạm để huỷ)",
                                             (long)_remaining]
               on:host];
    _remaining--;
}

- (NSString *)labelFor:(TMStream *)s {
    if ([s.kind isEqualToString:@"audio"]) return @"chỉ nghe";
    if ([s.kind isEqualToString:@"file"]) return @"đã tải";
    return [s.kind isEqualToString:@"hls"] ? [NSString stringWithFormat:@"%ldp (HLS)", (long)s.quality]
                                           : [NSString stringWithFormat:@"%ldp", (long)s.quality];
}

- (void)startPlayback {
    NSURL *url = [NSURL URLWithString:_stream.url];
    if (!url) {
        [self alert:@"Link phát không hợp lệ."];
        return;
    }
    self.playingLabel = [self labelFor:_stream];
    TMLog(@"[player] %@ %@", _video.videoID, self.playingLabel);
    if ([_stream.kind isEqualToString:@"audio"]) {
        // No screen of its own: the mini bar above the tab bar controls it
        self.playingLabel = nil;
        [[TMAudioPlayer shared] playURL:_stream.url video:_video startAt:_startAt];
        return;
    }
    if (_playerVC) {
        // Retry inside the open player, from where it stopped
        _playerVC.moviePlayer.initialPlaybackTime = _lastPosition;
        _playerVC.moviePlayer.contentURL = url;
        [_playerVC.moviePlayer play];
        return;
    }
    _playerVC = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
    // Handle the end of playback ourselves: by default the controller dismisses itself on errors too
    [[NSNotificationCenter defaultCenter] removeObserver:_playerVC
                                                    name:MPMoviePlayerPlaybackDidFinishNotification
                                                  object:_playerVC.moviePlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(finished:)
                                                 name:MPMoviePlayerPlaybackDidFinishNotification
                                               object:_playerVC.moviePlayer];
    _playerVC.moviePlayer.shouldAutoplay = YES;
    if (_startAt > 0) {
        TMLog(@"[player] xem tiếp từ %ld giây", (long)_startAt);
        _playerVC.moviePlayer.initialPlaybackTime = _startAt;
    }
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self loadArtwork];
    [_presenter presentMoviePlayerViewControllerAnimated:_playerVC];
    [_playerVC.moviePlayer prepareToPlay];
    [_playerVC.moviePlayer play];
    // Into the history right away, then every few seconds
    [self storePosition:_startAt];
    [_saveTimer invalidate];
    _saveTimer = [NSTimer scheduledTimerWithTimeInterval:kSaveInterval
                                                  target:self
                                                selector:@selector(saveProgress)
                                                userInfo:nil
                                                 repeats:YES];
}

#pragma mark - Audio only, lock screen

/// The thumbnail for the lock screen (MPMediaItemArtwork needs a UIImage).
- (void)loadArtwork {
    _artwork = nil;
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

/// Title, channel, picture, position and rate on the lock screen (iOS 5+).
- (void)updateNowPlaying {
    MPMoviePlayerController *p = _playerVC.moviePlayer;
    if (!p || !_video) {
        // Leave the lock screen to the audio player when it is the one playing
        if (![TMAudioPlayer shared].active) [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        return;
    }
    [self readPlayer];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = _video.title ?: @"";
    info[MPMediaItemPropertyArtist] = _video.author ?: @"TubeMini";
    if (_lastDuration > 0) info[MPMediaItemPropertyPlaybackDuration] = @(_lastDuration);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(_lastPosition);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(p.playbackState == MPMoviePlaybackStatePlaying ? 1.0 : 0.0);
    if (_artwork) info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:_artwork];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)remoteControl:(UIEvent *)event {
    if ([TMAudioPlayer shared].active) {
        [[TMAudioPlayer shared] remoteControl:event];
        return;
    }
    MPMoviePlayerController *p = _playerVC.moviePlayer;
    if (!p || event.type != UIEventTypeRemoteControl) return;
    BOOL play;
    switch (event.subtype) {
    case UIEventSubtypeRemoteControlTogglePlayPause: play = p.playbackState != MPMoviePlaybackStatePlaying; break;
    case UIEventSubtypeRemoteControlPlay: play = YES; break;
    case UIEventSubtypeRemoteControlPause:
    case UIEventSubtypeRemoteControlStop: play = NO; break;
    default: return;
    }
    // A pause by the user (lock screen, headphones) stays paused: the background guard leaves it alone
    _keepSound = play;
    if (play) {
        [p play];
    } else {
        [p pause];
    }
    TMLog(@"[player] điều khiển từ xa: %ld", (long)event.subtype);
    [self saveProgress];
}

#pragma mark - Background

/// iOS pauses a movie with video when the app leaves the screen (home button, lock). With the playback
/// audio session and UIBackgroundModes = audio, playing it again keeps the sound going in the background
/// (frames are not drawn; back on screen the picture continues). But while it is paused nothing keeps a
/// background app alive: iOS may suspend it right after didEnterBackground, before a delayed `play` runs,
/// and the sound is gone until the app is opened again (seen on the iPad mini 1, now and then). So a
/// background task keeps the app running while a guard checks every 0.25 s, for a few seconds, and plays
/// again whenever the movie is paused (iOS may pause it more than once). Once the sound plays, the audio
/// background mode keeps the app alive.
- (void)willResignActive {
    MPMoviePlayerController *p = _playerVC.moviePlayer;
    _keepSound = p && p.playbackState == MPMoviePlaybackStatePlaying;
    if (!_keepSound) return;
    _resumes = 0;
    [self guardFor:3]; // locking the screen may only make the app inactive
}

- (void)didEnterBackground {
    [self saveProgress];
    if (_keepSound && _playerVC) [self guardFor:4];
}

- (void)didBecomeActive {
    [self stopGuard];
}

/// Another app took the sound (or an alarm): don't fight it.
- (void)audioInterrupted:(NSNotification *)n {
    if ([n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] != AVAudioSessionInterruptionTypeBegan) return;
    if (!_guard) return;
    TMLog(@"[player] âm thanh bị app khác chiếm, không phát tiếp");
    _keepSound = NO;
    [self stopGuard];
}

- (void)guardFor:(NSTimeInterval)seconds {
    _guardUntil = MAX(_guardUntil, [NSDate timeIntervalSinceReferenceDate] + seconds);
    if (_bgTask == UIBackgroundTaskInvalid) {
        _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ [self stopGuard]; }];
    }
    if (!_guard) {
        // Common modes: also fires while UIKit runs the loop in its own mode during the app switch
        _guard = [NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(guardTick) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_guard forMode:NSRunLoopCommonModes];
    }
}

- (void)guardTick {
    MPMoviePlayerController *p = _playerVC.moviePlayer;
    if (!p || !_keepSound) {
        [self stopGuard];
        return;
    }
    BOOL away = [UIApplication sharedApplication].applicationState != UIApplicationStateActive;
    // Paused by iOS: a pause by the user went through remoteControl: and cleared _keepSound
    if (away && p.playbackState == MPMoviePlaybackStatePaused && _resumes < 10) {
        _resumes++;
        TMLog(@"[player] app xuống nền: phát tiếp tiếng (lần %ld)", (long)_resumes);
        [p play];
    }
    if ([NSDate timeIntervalSinceReferenceDate] < _guardUntil) return;
    if (away && _resumes) {
        BOOL playing = p.playbackState == MPMoviePlaybackStatePlaying;
        TMLog(@"[player] nền: %@", playing ? @"đang phát tiếng"
                                           : [NSString stringWithFormat:@"không phát tiếp được (trạng thái %ld)",
                                                                        (long)p.playbackState]);
    }
    [self stopGuard];
}

- (void)stopGuard {
    [_guard invalidate];
    _guard = nil;
    _guardUntil = 0;
    if (_bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
        _bgTask = UIBackgroundTaskInvalid;
    }
}

- (void)playbackStateChanged:(NSNotification *)n {
    [self updateNowPlaying];
}

#pragma mark - Watch position

/// Reads position / duration from the player (when it knows them) and saves the position.
- (void)saveProgress {
    MPMoviePlayerController *p = _playerVC.moviePlayer;
    if (!p || !_video) return;
    [self readPlayer];
    [self storePosition:_lastPosition];
}

- (void)readPlayer {
    MPMoviePlayerController *p = _playerVC.moviePlayer;
    NSTimeInterval t = p.currentPlaybackTime, d = p.duration;
    if (isfinite(t) && t > 0) _lastPosition = (NSInteger)t;
    if (isfinite(d) && d > 0) _lastDuration = (NSInteger)d;
}

- (void)storePosition:(NSInteger)position {
    if (!_video.videoID.length) return;
    [[TMAPIClient shared] savePosition:position duration:_lastDuration video:_video];
    [[TMLibrary shared] historyChangedForVideo:_video.videoID position:position duration:_lastDuration];
    [self updateNowPlaying];
}

- (void)dismissPlayer {
    [_saveTimer invalidate];
    _saveTimer = nil;
    _keepSound = NO;
    [self stopGuard];
    if (!_playerVC) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:MPMoviePlayerPlaybackDidFinishNotification
                                                  object:_playerVC.moviePlayer];
    [_playerVC.moviePlayer stop];
    [_presenter dismissMoviePlayerViewControllerAnimated];
    _playerVC = nil;
    self.playingLabel = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    if (![TMAudioPlayer shared].active) {
        [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    }
}

- (void)finished:(NSNotification *)n {
    NSInteger reason = [n.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    if (reason != MPMovieFinishReasonPlaybackError) {
        [self readPlayer];
        // Watched to the end: next time starts over (see +[TMLibrary resumePositionFor:duration:])
        [self storePosition:reason == MPMovieFinishReasonPlaybackEnded && _lastDuration ? _lastDuration : _lastPosition];
        [self dismissPlayer];
        return;
    }
    TMLog(@"[player] lỗi phát %@ (%@): %@", _video.videoID, self.playingLabel, n.userInfo[@"error"]);
    if (!_retried) {
        // Expired / refused link: ask the server for a fresh one, once
        _retried = YES;
        [self showHUD:@"Link lỗi, đang lấy link mới…" on:_playerVC.view];
        [self fetchStreams:YES];
        return;
    }
    TMStream *mp4 = [_streams streamOfKind:@"mp4"];
    BOOL canFallBack = ([_stream.kind isEqualToString:@"hls"] || [_stream.kind isEqualToString:@"audio"]) && mp4;
    BOOL local = _localPath != nil;
    [self dismissPlayer];
    if (local) {
        [self alert:@"Không phát được bản đã tải. Có thể file bị hỏng: xoá rồi tải lại."];
    } else if (canFallBack) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Không phát được"
                                                    message:[NSString stringWithFormat:@"Không phát được ở %@. Thử 360p?",
                                                                                       [self labelFor:_stream]]
                                                   delegate:self
                                          cancelButtonTitle:@"Đóng"
                                          otherButtonTitles:@"Thử 360p", nil];
        [a show];
    } else {
        [self alert:@"Video này không phát được. Thử lại sau, hoặc chọn video khác."];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex || !_presenter) return;
    [self playVideo:_video quality:360 startAt:_lastPosition from:_presenter];
}

@end
