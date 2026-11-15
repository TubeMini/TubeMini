#import "TMDebug.h"
#import "TMAppDelegate.h"
#import "TMLog.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>

static MPMoviePlayerViewController *gPlayerVC;
/// Headless AVPlayer for `avplay`: reports which tracks (video / audio) are really playing.
static AVPlayer *gAVPlayer;

@implementation TMDebug

+ (void)start {
    TMLog(@"[debug] lệnh qua %@", [self cmdPath]);
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (NSString *name in @[ MPMoviePlayerLoadStateDidChangeNotification, MPMoviePlayerPlaybackStateDidChangeNotification,
                              MPMovieNaturalSizeAvailableNotification, MPMovieDurationAvailableNotification ]) {
        [nc addObserver:self selector:@selector(playerEvent:) name:name object:nil];
    }
    [nc addObserver:self selector:@selector(playerFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    [NSTimer scheduledTimerWithTimeInterval:0.7 target:self selector:@selector(poll) userInfo:nil repeats:YES];
}

+ (NSString *)cmdPath {
    return [TMDocumentsDir() stringByAppendingPathComponent:@"TubeMini-cmd.txt"];
}

+ (void)poll {
    // Debug build: keep the screen on, otherwise the iPad locks, drops Wi-Fi and SSH is lost
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    NSString *path = [self cmdPath];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!text) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    NSMutableArray *cmds = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *cmd = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (cmd.length && ![cmd hasPrefix:@"#"]) [cmds addObject:cmd];
    }
    [self runAll:cmds];
}

+ (void)runAll:(NSArray *)cmds {
    for (NSUInteger i = 0; i < cmds.count; i++) {
        NSString *cmd = cmds[i];
        if ([cmd hasPrefix:@"wait"]) {
            double s = [[cmd substringFromIndex:4] doubleValue];
            NSArray *rest = [cmds subarrayWithRange:NSMakeRange(i + 1, cmds.count - i - 1)];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((s > 0 ? s : 1) * NSEC_PER_SEC)), dispatch_get_main_queue(),
                           ^{ [self runAll:rest]; });
            return;
        }
        [self run:cmd];
    }
}

+ (void)run:(NSString *)cmd {
    NSRange sp = [cmd rangeOfString:@" "];
    NSString *verb = sp.location == NSNotFound ? cmd : [cmd substringToIndex:sp.location];
    NSString *arg = sp.location == NSNotFound
                        ? @""
                        : [[cmd substringFromIndex:sp.location + 1]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // Do not log full googlevideo URLs (long, and they carry the requester IP)
    TMLog(@"[debug] > %@ %@", verb, arg.length > 80 ? [[arg substringToIndex:80] stringByAppendingString:@"…"] : arg);

    if ([verb isEqualToString:@"shot"]) {
        [self shot:arg.length ? arg : @"shot"];
    } else if ([verb isEqualToString:@"net"]) {
        [self net:arg];
    } else if ([verb isEqualToString:@"play"]) {
        [self play:arg];
    } else if ([verb isEqualToString:@"status"]) {
        [self status];
    } else if ([verb isEqualToString:@"frame"]) {
        [self frame:arg.length ? arg : @"frame"];
    } else if ([verb isEqualToString:@"avplay"]) {
        NSURL *url = [NSURL URLWithString:arg];
        [gAVPlayer pause];
        gAVPlayer = url ? [AVPlayer playerWithURL:url] : nil;
        [gAVPlayer play];
    } else if ([verb isEqualToString:@"avstatus"]) {
        [self avStatus];
    } else if ([verb isEqualToString:@"avstop"]) {
        [gAVPlayer pause];
        gAVPlayer = nil;
    } else if ([verb isEqualToString:@"seek"]) {
        gPlayerVC.moviePlayer.currentPlaybackTime = [arg doubleValue];
    } else if ([verb isEqualToString:@"stop"]) {
        [gPlayerVC.moviePlayer stop];
        [[self nav] dismissMoviePlayerViewControllerAnimated];
        gPlayerVC = nil;
    } else if ([verb isEqualToString:@"mark"]) {
        TMLog(@"[debug] ==== %@", arg);
    } else {
        TMLog(@"[debug] lệnh lạ: %@", verb);
    }
}

+ (UINavigationController *)nav {
    return [(TMAppDelegate *)[UIApplication sharedApplication].delegate nav];
}

#pragma mark - net

+ (void)net:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        TMLog(@"[net] URL sai");
        return;
    }
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25];
    NSDate *t0 = [NSDate date];
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
                               int ms = (int)(-[t0 timeIntervalSinceNow] * 1000);
                               if (err) {
                                   TMLog(@"[net] %@ → LỖI %ld %@ (%@), %d ms", url.host, (long)err.code, err.domain,
                                         err.localizedDescription, ms);
                                   return;
                               }
                               NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
                               TMLog(@"[net] %@ → HTTP %ld, %lu byte, %@, %d ms", url.host, (long)http.statusCode,
                                     (unsigned long)data.length, http.allHeaderFields[@"Content-Type"], ms);
                           }];
}

#pragma mark - player

+ (void)play:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        TMLog(@"[play] URL sai");
        return;
    }
    if (gPlayerVC) {
        [gPlayerVC.moviePlayer stop];
        [[self nav] dismissMoviePlayerViewControllerAnimated];
    }
    gPlayerVC = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
    gPlayerVC.moviePlayer.shouldAutoplay = YES;
    [[self nav] presentMoviePlayerViewControllerAnimated:gPlayerVC];
    [gPlayerVC.moviePlayer prepareToPlay];
    [gPlayerVC.moviePlayer play];
}

+ (NSString *)playbackStateName:(MPMoviePlaybackState)s {
    switch (s) {
    case MPMoviePlaybackStateStopped: return @"stopped";
    case MPMoviePlaybackStatePlaying: return @"playing";
    case MPMoviePlaybackStatePaused: return @"paused";
    case MPMoviePlaybackStateInterrupted: return @"interrupted";
    case MPMoviePlaybackStateSeekingForward: return @"seekFwd";
    case MPMoviePlaybackStateSeekingBackward: return @"seekBack";
    }
    return @"?";
}

+ (NSString *)loadStateName:(MPMovieLoadState)s {
    NSMutableArray *parts = [NSMutableArray array];
    if (s & MPMovieLoadStatePlayable) [parts addObject:@"playable"];
    if (s & MPMovieLoadStatePlaythroughOK) [parts addObject:@"throughOK"];
    if (s & MPMovieLoadStateStalled) [parts addObject:@"stalled"];
    return parts.count ? [parts componentsJoinedByString:@"+"] : @"unknown";
}

+ (void)playerEvent:(NSNotification *)n {
    MPMoviePlayerController *p = n.object;
    TMLog(@"[play] %@: state=%@ load=%@ t=%.1f/%.1f", [n.name stringByReplacingOccurrencesOfString:@"Notification" withString:@""],
          [self playbackStateName:p.playbackState], [self loadStateName:p.loadState], p.currentPlaybackTime, p.duration);
}

+ (void)playerFinished:(NSNotification *)n {
    NSNumber *reason = n.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    NSError *err = n.userInfo[@"error"];
    TMLog(@"[play] kết thúc: lý do=%@ (0=hết,1=lỗi,2=người dùng) lỗi=%@", reason, err ?: @"không");
    [self logErrorLog:n.object];
}

+ (void)logErrorLog:(MPMoviePlayerController *)p {
    for (MPMovieErrorLogEvent *e in p.errorLog.events) {
        TMLog(@"[play] errorLog: %ld %@ — %@ (%@)", (long)e.errorStatusCode, e.errorDomain, e.errorComment, e.URI.length > 60 ? [e.URI substringToIndex:60] : e.URI);
    }
}

+ (void)status {
    MPMoviePlayerController *p = gPlayerVC.moviePlayer;
    if (!p) {
        TMLog(@"[status] không có trình phát");
        return;
    }
    TMLog(@"[status] state=%@ load=%@ t=%.1f playable=%.1f duration=%.1f size=%.0fx%.0f", [self playbackStateName:p.playbackState],
          [self loadStateName:p.loadState], p.currentPlaybackTime, p.playableDuration, p.duration, p.naturalSize.width,
          p.naturalSize.height);
    MPMovieAccessLogEvent *a = p.accessLog.events.lastObject;
    if (a) {
        TMLog(@"[status] accessLog: %@ bytes=%lld stalls=%ld observedBitrate=%.0f indicatedBitrate=%.0f",
              a.serverAddress, a.numberOfBytesTransferred, (long)a.numberOfStalls, a.observedBitrate, a.indicatedBitrate);
    }
    [self logErrorLog:p];
}

+ (void)avStatus {
    AVPlayerItem *item = gAVPlayer.currentItem;
    if (!item) {
        TMLog(@"[av] không có AVPlayer");
        return;
    }
    TMLog(@"[av] status=%ld rate=%.1f t=%.1f size=%.0fx%.0f error=%@", (long)item.status, gAVPlayer.rate,
          CMTimeGetSeconds(item.currentTime), item.presentationSize.width, item.presentationSize.height,
          item.error.localizedDescription ?: @"không");
    for (AVPlayerItemTrack *t in item.tracks) {
        AVAssetTrack *a = t.assetTrack;
        TMLog(@"[av] track %@ enabled=%d format=%@", a.mediaType, t.enabled,
              a.formatDescriptions.count ? @"có" : @"(HLS: không báo)");
    }
    AVPlayerItemAccessLogEvent *e = item.accessLog.events.lastObject;
    if (e) {
        TMLog(@"[av] accessLog bytes=%lld indicatedBitrate=%.0f server=%@", e.numberOfBytesTransferred,
              e.indicatedBitrate, e.serverAddress);
    }
}

#pragma mark - screenshot

/// Decoded video frame at the current position (UIGetScreenImage cannot see MPMoviePlayer's video layer)
+ (void)frame:(NSString *)name {
    MPMoviePlayerController *p = gPlayerVC.moviePlayer;
    if (!p) {
        TMLog(@"[frame] không có trình phát");
        return;
    }
    UIImage *img = [p thumbnailImageAtTime:p.currentPlaybackTime timeOption:MPMovieTimeOptionNearestKeyFrame];
    if (!img) {
        TMLog(@"[frame] không lấy được khung hình tại t=%.1f", p.currentPlaybackTime);
        return;
    }
    NSString *dir = [TMDocumentsDir() stringByAppendingPathComponent:@"TubeMini-shots"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"jpg"]];
    [UIImageJPEGRepresentation(img, 0.8) writeToFile:path atomically:YES];
    TMLog(@"[frame] %@ (%.0fx%.0f) t=%.1f", path, img.size.width * img.scale, img.size.height * img.scale, p.currentPlaybackTime);
}

/// UIGetScreenImage (private, captures video layers too); falls back to rendering the key window
+ (void)shot:(NSString *)name {
    NSString *dir = [TMDocumentsDir() stringByAppendingPathComponent:@"TubeMini-shots"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    UIImage *img = nil;
    CGImageRef (*grab)(void) = (CGImageRef(*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
    if (grab) {
        CGImageRef cg = grab();
        if (cg) {
            img = [UIImage imageWithCGImage:cg];
            CGImageRelease(cg);
        }
    }
    if (!img) {
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0);
        [w.layer renderInContext:UIGraphicsGetCurrentContext()];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    TMLog(@"[shot] %@ (%.0fx%.0f)", path, img.size.width * img.scale, img.size.height * img.scale);
}

@end
