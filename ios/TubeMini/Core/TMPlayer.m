#import "TMPlayer.h"
#import "TMAPIClient.h"
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
}

+ (instancetype)shared {
    static TMPlayer *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[TMPlayer alloc] init]; });
    return p;
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
    _generation++;
    _video = video;
    _quality = quality;
    _presenter = presenter;
    _retried = NO;
    [self showHUD:@"Đang lấy link phát…" on:presenter.view.window ?: presenter.view];
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
    UIView *host = _playerVC ? _playerVC.view : (_presenter.view.window ?: _presenter.view);
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
        // Retry inside the open player
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
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [_presenter presentMoviePlayerViewControllerAnimated:_playerVC];
    [_playerVC.moviePlayer prepareToPlay];
    [_playerVC.moviePlayer play];
}

- (void)dismissPlayer {
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
    [self playVideo:_video quality:360 from:_presenter];
}

@end
