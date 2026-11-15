#import "TMAppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "TMAPIClient.h"
#import "TMAudioBar.h"
#import "TMAudioPlayer.h"
#import "TMDownloads.h"
#import "TMVideoViewController.h"
#import "TMDownloadsViewController.h"
#import "TMPlayer.h"
#import "TMUpdater.h"
#import "TMImageLoader.h"
#import "TMHomeViewController.h"
#import "TMLibrary.h"
#import "TMListViewController.h"
#import "TMLog.h"
#import "TMSearchViewController.h"
#import "TMSettingsViewController.h"
#import "TMSubscriptionsViewController.h"
#import "TMTheme.h"
#ifdef TM_DEBUG
#import "TMDebug.h"
#endif

typedef void (^TMDrawBlock)(CGContextRef ctx);

/// Tab bar icons drawn at runtime (30×30 alpha masks), so the app needs no image assets.
static UIImage *icon(TMDrawBlock draw) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
    CGContextSetStrokeColorWithColor(ctx, [UIColor blackColor].CGColor);
    CGContextSetLineWidth(ctx, 3);
    draw(ctx);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@implementation TMAppDelegate

- (UINavigationController *)nav {
    UIViewController *vc = self.tabs.selectedViewController;
    return [vc isKindOfClass:[UINavigationController class]] ? (UINavigationController *)vc : nil;
}

- (UINavigationController *)wrap:(UIViewController *)vc title:(NSString *)title image:(UIImage *)image {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:image tag:0];
    return nav;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    TMLog(@"TubeMini %@ khởi động — iOS %@, %@", info[@"CFBundleShortVersionString"],
          [UIDevice currentDevice].systemVersion, TMDeviceModel());
    [TMImageLoader shared]; // registers for memory warnings early
    [TMTheme applyGlobalAppearance]; // light or dark, before any bar is created
    // Playback category: sound ignores the silent switch, and "Chỉ nghe" keeps playing with the screen
    // locked or in the background (UIBackgroundModes = audio in Info.plist)
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    TMHomeViewController *home = [[TMHomeViewController alloc] init];

    UIImage *homeIcon = icon(^(CGContextRef ctx) {
        CGContextMoveToPoint(ctx, 15, 3);
        CGContextAddLineToPoint(ctx, 28, 15);
        CGContextAddLineToPoint(ctx, 2, 15);
        CGContextFillPath(ctx);
        CGContextFillRect(ctx, CGRectMake(6, 14, 18, 13));
    });
    UIImage *searchIcon = icon(^(CGContextRef ctx) {
        CGContextStrokeEllipseInRect(ctx, CGRectMake(4, 4, 15, 15));
        CGContextSetLineWidth(ctx, 4);
        CGContextMoveToPoint(ctx, 17, 17);
        CGContextAddLineToPoint(ctx, 26, 26);
        CGContextStrokePath(ctx);
    });
    UIImage *subscriptionsIcon = icon(^(CGContextRef ctx) {
        // A stack of screens with a play triangle cut out of the front one
        CGContextFillRect(ctx, CGRectMake(10, 3, 10, 2));
        CGContextFillRect(ctx, CGRectMake(6, 7, 18, 2));
        CGContextFillRect(ctx, CGRectMake(2, 11, 26, 17));
        CGContextSetBlendMode(ctx, kCGBlendModeClear);
        CGContextMoveToPoint(ctx, 12, 14);
        CGContextAddLineToPoint(ctx, 12, 25);
        CGContextAddLineToPoint(ctx, 21, 19.5);
        CGContextFillPath(ctx);
    });
    UIImage *historyIcon = icon(^(CGContextRef ctx) {
        CGContextStrokeEllipseInRect(ctx, CGRectMake(3, 3, 24, 24));
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextMoveToPoint(ctx, 15, 8);
        CGContextAddLineToPoint(ctx, 15, 15);
        CGContextAddLineToPoint(ctx, 20, 19);
        CGContextStrokePath(ctx);
    });
    UIImage *downloadsIcon = icon(^(CGContextRef ctx) {
        // Arrow down into a tray
        CGContextFillRect(ctx, CGRectMake(12.5, 2, 5, 11));
        CGContextMoveToPoint(ctx, 6, 12);
        CGContextAddLineToPoint(ctx, 24, 12);
        CGContextAddLineToPoint(ctx, 15, 21);
        CGContextFillPath(ctx);
        CGContextMoveToPoint(ctx, 3.5, 18);
        CGContextAddLineToPoint(ctx, 3.5, 26.5);
        CGContextAddLineToPoint(ctx, 26.5, 26.5);
        CGContextAddLineToPoint(ctx, 26.5, 18);
        CGContextStrokePath(ctx);
    });
    UIImage *settingsIcon = icon(^(CGContextRef ctx) {
        for (int i = 0; i < 8; i++) {
            CGFloat a = i * M_PI / 4;
            CGContextFillEllipseInRect(ctx, CGRectMake(15 + 10 * cos(a) - 3, 15 + 10 * sin(a) - 3, 6, 6));
        }
        CGContextFillEllipseInRect(ctx, CGRectMake(7, 7, 16, 16));
    });

    self.tabs = [[UITabBarController alloc] init];
    self.tabs.viewControllers = @[
        [self wrap:home title:@"Trang chủ" image:homeIcon],
        [self wrap:[[TMSearchViewController alloc] init] title:@"Tìm kiếm" image:searchIcon],
        [self wrap:[[TMSubscriptionsViewController alloc] init] title:@"Đã theo dõi" image:subscriptionsIcon],
        [self wrap:[[TMHistoryViewController alloc] init] title:@"Lịch sử" image:historyIcon],
        [self wrap:[[TMDownloadsViewController alloc] init] title:@"Đã tải" image:downloadsIcon],
        [self wrap:[[TMSettingsViewController alloc] init] title:@"Cài đặt" image:settingsIcon],
    ];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [TMTheme current].background;
    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];
    [self addAudioBar];

    [[TMLibrary shared] refresh]; // which channels are subscribed (for the Subscribe buttons)
    if (![TMAPIClient shared].isConfigured) {
        self.tabs.selectedIndex = self.tabs.viewControllers.count - 1; // Cài đặt
        [[[UIAlertView alloc] initWithTitle:@"Chào mừng đến TubeMini"
                                    message:@"Nhập địa chỉ máy chủ tubemini-server trong mạng nhà để bắt đầu."
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    }
    [[TMDownloads shared] resume]; // downloads interrupted last time
    if ([TMAPIClient shared].isConfigured) [[TMUpdater shared] checkQuietly]; // a newer TubeMini? (once a day)
#ifdef TM_DEBUG
    [TMDebug start];
#endif
    return YES;
}

/// The "Chỉ nghe" mini player, just above the tab bar, on the view that rotates.
- (void)addAudioBar {
    UIView *host = self.tabs.view;
    CGFloat h = [TMAudioBar height], tab = self.tabs.tabBar.bounds.size.height;
    TMAudioBar *bar = [[TMAudioBar alloc] initWithFrame:CGRectMake(0, host.bounds.size.height - tab - h, host.bounds.size.width, h)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    __weak TMAppDelegate *weakSelf = self;
    bar.onOpen = ^{
        TMVideo *v = [TMAudioPlayer shared].video;
        UINavigationController *nav = [weakSelf nav];
        UIViewController *top = nav.topViewController;
        if (!v || !nav) return;
        if ([top isKindOfClass:[TMVideoViewController class]] && [[(TMVideoViewController *)top video].videoID isEqualToString:v.videoID]) return;
        [nav pushViewController:[[TMVideoViewController alloc] initWithVideo:v] animated:YES];
    };
    [host addSubview:bar];
}

/// Lock screen / headphone buttons reach the end of the responder chain here.
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    [[TMPlayer shared] remoteControl:event];
}

@end
