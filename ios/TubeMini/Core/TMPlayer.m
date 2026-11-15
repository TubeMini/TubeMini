#import "TMPlayer.h"
#import "TMAPIClient.h"
#import "TMLibrary.h"
#import "TMLog.h"
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(saveProgress)
                                                     name:UIApplicationDidEnterBackgroundNotification
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
}

- (void)dismissPlayer {
    [_saveTimer invalidate];
    _saveTimer = nil;
    if (!_playerVC) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:MPMoviePlayerPlaybackDidFinishNotification
                                                  object:_playerVC.moviePlayer];
    [_playerVC.moviePlayer stop];
    [_presenter dismissMoviePlayerViewControllerAnimated];
    _playerVC = nil;
    self.playingLabel = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
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
    BOOL canFallBack = [_stream.kind isEqualToString:@"hls"] && mp4;
    [self dismissPlayer];
    if (canFallBack) {
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
