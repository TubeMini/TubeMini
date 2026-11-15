#import "TMDebug.h"
#import "TMAppDelegate.h"
#import "TMAPIClient.h"
#import "TMGridViewController.h"
#import "TMHomeViewController.h"
#import "TMTheme.h"
#import "TMListViewController.h"
#import "TMPlayer.h"
#import "TMSearchViewController.h"
#import "TMSettingsViewController.h"
#import "TMVideoViewController.h"
#import "TMLog.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <mach/mach.h>

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
        [self activePlayer].currentPlaybackTime = [arg doubleValue];
    } else if ([verb isEqualToString:@"stop"]) {
        [gPlayerVC.moviePlayer stop];
        [[self nav] dismissMoviePlayerViewControllerAnimated];
        gPlayerVC = nil;
    } else if ([verb isEqualToString:@"server"]) {
        [TMAPIClient shared].serverURL = arg;
        [self reloadSettingsScreen];
        TMLog(@"[debug] server = %@", [TMAPIClient shared].serverURL);
    } else if ([verb isEqualToString:@"quality"]) {
        [TMAPIClient shared].preferredQuality = [arg integerValue];
        [self reloadSettingsScreen];
    } else if ([verb isEqualToString:@"tab"]) {
        [self app].tabs.selectedIndex = (NSUInteger)[arg integerValue];
    } else if ([verb isEqualToString:@"search"]) {
        // "search <query>" for videos, "search ch:<query>" for channels
        TMAppDelegate *app = [self app];
        app.tabs.selectedIndex = 1;
        UINavigationController *nav = [app nav];
        [nav popToRootViewControllerAnimated:NO];
        TMSearchViewController *search = (TMSearchViewController *)nav.viewControllers[0];
        BOOL channels = [arg hasPrefix:@"ch:"];
        [search runSearch:channels ? [arg substringFromIndex:3] : arg scope:channels ? 1 : 0];
    } else if ([verb isEqualToString:@"open"]) {
        UIViewController *top = [self topScreen];
        if ([top isKindOfClass:[TMListViewController class]]) [(TMListViewController *)top selectRow:[arg integerValue]];
        if ([top isKindOfClass:[TMGridViewController class]]) [(TMGridViewController *)top selectItem:[arg integerValue]];
    } else if ([verb isEqualToString:@"theme"]) {
        [TMTheme setDark:[arg isEqualToString:@"dark"]];
    } else if ([verb isEqualToString:@"homemode"]) {
        UINavigationController *homeNav = (UINavigationController *)[self app].tabs.viewControllers[0];
        UIViewController *home = homeNav.viewControllers[0];
        if ([home isKindOfClass:[TMHomeViewController class]]) [(TMHomeViewController *)home setGridMode:[arg isEqualToString:@"grid"]];
    } else if ([verb isEqualToString:@"playbtn"]) {
        UIViewController *top = [self nav].topViewController;
        if ([top isKindOfClass:[TMVideoViewController class]]) [(TMVideoViewController *)top play];
    } else if ([verb isEqualToString:@"section"]) {
        UIViewController *top = [self nav].topViewController;
        if ([top isKindOfClass:[TMVideoViewController class]]) [(TMVideoViewController *)top showSection:[arg integerValue]];
    } else if ([verb isEqualToString:@"scrollend"]) {
        UIViewController *top = [self topScreen];
        UIScrollView *sv = nil;
        if ([top isKindOfClass:[UITableViewController class]]) sv = ((UITableViewController *)top).tableView;
        if ([top isKindOfClass:[UICollectionViewController class]]) sv = ((UICollectionViewController *)top).collectionView;
        [sv setContentOffset:CGPointMake(0, MAX(0, sv.contentSize.height - sv.bounds.size.height)) animated:NO];
    } else if ([verb isEqualToString:@"back"]) {
        [[self nav] popViewControllerAnimated:NO];
    } else if ([verb isEqualToString:@"pingtest"]) {
        TMAppDelegate *app = [self app];
        app.tabs.selectedIndex = 2;
        UIViewController *root = [app nav].viewControllers[0];
        if ([root isKindOfClass:[TMSettingsViewController class]]) [(TMSettingsViewController *)root testConnection];
    } else if ([verb isEqualToString:@"dismissalert"]) {
        [self dismissAlerts];
    } else if ([verb isEqualToString:@"ui"]) {
        [self logUI];
    } else if ([verb isEqualToString:@"mem"]) {
        struct task_basic_info info;
        mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
            TMLog(@"[mem] resident %.1f MB, virtual %.1f MB", info.resident_size / 1048576.0, info.virtual_size / 1048576.0);
        }
    } else if ([verb isEqualToString:@"rotate"]) {
        // Simulates turning the iPad (private -[UIDevice setOrientation:], debug builds only)
        UIDeviceOrientation o = [arg isEqualToString:@"left"]    ? UIDeviceOrientationLandscapeLeft
                                : [arg isEqualToString:@"right"] ? UIDeviceOrientationLandscapeRight
                                                                 : UIDeviceOrientationPortrait;
        SEL sel = NSSelectorFromString(@"setOrientation:");
        if ([[UIDevice currentDevice] respondsToSelector:sel]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)([UIDevice currentDevice], sel, o);
        }
    } else if ([verb isEqualToString:@"mark"]) {
        TMLog(@"[debug] ==== %@", arg);
    } else {
        TMLog(@"[debug] lệnh lạ: %@", verb);
    }
}

/// The settings screen keeps its own text fields: refresh them after changing settings here.
+ (void)reloadSettingsScreen {
    for (UIViewController *vc in [self app].tabs.viewControllers) {
        UIViewController *root = [vc isKindOfClass:[UINavigationController class]] ? ((UINavigationController *)vc).viewControllers[0] : vc;
        if ([root isKindOfClass:[TMSettingsViewController class]] && root.isViewLoaded) {
            [(TMSettingsViewController *)root reloadFields];
        }
    }
}

+ (TMAppDelegate *)app {
    return (TMAppDelegate *)[UIApplication sharedApplication].delegate;
}

/// The app's player when one is on screen, otherwise the debug `play` player.
+ (MPMoviePlayerController *)activePlayer {
    return [TMPlayer shared].moviePlayer ?: gPlayerVC.moviePlayer;
}

+ (void)dismissAlerts {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        for (UIView *v in w.subviews) {
            [self dismissAlertsIn:v];
        }
    }
}

+ (void)dismissAlertsIn:(UIView *)v {
    if ([v isKindOfClass:[UIAlertView class]]) {
        UIAlertView *a = (UIAlertView *)v;
        TMLog(@"[debug] alert: %@ — %@", a.title, a.message);
        [a dismissWithClickedButtonIndex:a.cancelButtonIndex animated:NO];
        return;
    }
    for (UIView *s in v.subviews) [self dismissAlertsIn:s];
}

/// One line describing where the app is: tab, top screen, rows, footer text, visible alerts.
/// Top screen of the current tab, looking through the home container to its list / grid.
+ (UIViewController *)topScreen {
    UIViewController *top = [self nav].topViewController;
    if ([top isKindOfClass:[TMHomeViewController class]]) return [(TMHomeViewController *)top activeChild];
    return top;
}

+ (void)logUI {
    TMAppDelegate *app = [self app];
    UIViewController *top = [self topScreen];
    NSMutableString *line = [NSMutableString stringWithFormat:@"[ui] tab=%lu top=%@ title=%@", (unsigned long)app.tabs.selectedIndex,
                                                              NSStringFromClass([top class]), top.title];
    NSArray *items = nil;
    if ([top isKindOfClass:[TMListViewController class]]) items = ((TMListViewController *)top).items;
    if ([top isKindOfClass:[TMGridViewController class]]) items = ((TMGridViewController *)top).items;
    [line appendFormat:@" dark=%d", [TMTheme isDark]];
    if (items) {
        [line appendFormat:@" rows=%lu", (unsigned long)items.count];
        if (items.count) {
            id first = items[0];
            if ([first respondsToSelector:@selector(title)]) [line appendFormat:@" first=\"%@\"", [first valueForKey:@"title"]];
            else if ([first respondsToSelector:@selector(name)]) [line appendFormat:@" first=\"%@\"", [first valueForKey:@"name"]];
            else if ([first respondsToSelector:@selector(text)]) [line appendFormat:@" first=\"%@\"", [first valueForKey:@"text"]];
        }
    }
    if (top.presentedViewController) [line appendFormat:@" presented=%@", NSStringFromClass([top.presentedViewController class])];
    TMLog(@"%@", line);
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
    MPMoviePlayerController *p = [self activePlayer];
    if ([TMPlayer shared].playingLabel) TMLog(@"[status] app player: %@", [TMPlayer shared].playingLabel);
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
    MPMoviePlayerController *p = [self activePlayer];
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
