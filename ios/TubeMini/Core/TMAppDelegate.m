#import "TMAppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "TMAPIClient.h"
#import "TMAlert.h"
#import "TMNavigationController.h"
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

@implementation TMAppDelegate

- (UINavigationController *)nav {
    UIViewController *vc = self.tabs.selectedViewController;
    return [vc isKindOfClass:[UINavigationController class]] ? (UINavigationController *)vc : nil;
}

- (UINavigationController *)wrap:(UIViewController *)vc {
    return [[TMNavigationController alloc] initWithRootViewController:vc];
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

    // Search is the round button at the right end of the bar (iOS 26); the indexes stay those of the
    // old tab bar (debug commands: tab 5 = Cài đặt)
    self.tabs = [[TMTabBarController alloc] init];
    self.tabs.viewControllers = @[
        [self wrap:[[TMHomeViewController alloc] init]],
        [self wrap:[[TMSearchViewController alloc] init]],
        [self wrap:[[TMSubscriptionsViewController alloc] init]],
        [self wrap:[[TMHistoryViewController alloc] init]],
        [self wrap:[[TMDownloadsViewController alloc] init]],
        [self wrap:[[TMSettingsViewController alloc] init]],
    ];
    self.tabs.items = @[
        [TMTabItem itemWithTitle:@"Trang chủ" icon:@"home"],
        [TMTabItem itemWithTitle:@"Tìm kiếm" icon:@"search"],
        [TMTabItem itemWithTitle:@"Theo dõi" icon:@"subs"],
        [TMTabItem itemWithTitle:@"Lịch sử" icon:@"history"],
        [TMTabItem itemWithTitle:@"Đã tải" icon:@"download"],
        [TMTabItem itemWithTitle:@"Cài đặt" icon:@"settings"],
    ];
    self.tabs.accessoryIndex = 1;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [TMTheme current].background;
    self.window.rootViewController = self.tabs;
    [self addAudioBar];
    [self.window makeKeyAndVisible];

    [[TMLibrary shared] refresh]; // which channels are subscribed (for the Subscribe buttons)
    if (![TMAPIClient shared].isConfigured) {
        self.tabs.selectedIndex = self.tabs.viewControllers.count - 1; // Cài đặt
        dispatch_async(dispatch_get_main_queue(), ^{
            [TMAlert showTitle:@"Chào mừng đến TubeMini"
                       message:@"Nhập địa chỉ máy chủ tubemini-server trong mạng nhà để bắt đầu."
                        button:@"Bắt đầu"];
        });
    }
    [[TMDownloads shared] resume]; // downloads interrupted last time
    if ([TMAPIClient shared].isConfigured) [[TMUpdater shared] checkQuietly]; // a newer TubeMini? (once a day)
#ifdef TM_DEBUG
    [TMDebug start];
#endif
    return YES;
}

/// The "Chỉ nghe" mini player, floating just above the tab bar.
- (void)addAudioBar {
    TMAudioBar *bar = [[TMAudioBar alloc] initWithFrame:CGRectZero];
    __weak TMAppDelegate *weakSelf = self;
    bar.onOpen = ^{
        TMVideo *v = [TMAudioPlayer shared].video;
        UINavigationController *nav = [weakSelf nav];
        UIViewController *top = nav.topViewController;
        if (!v || !nav) return;
        if ([top isKindOfClass:[TMVideoViewController class]] && [[(TMVideoViewController *)top video].videoID isEqualToString:v.videoID]) return;
        [nav pushViewController:[[TMVideoViewController alloc] initWithVideo:v] animated:YES];
    };
    self.tabs.accessoryView = bar;
}

/// Lock screen / headphone buttons reach the end of the responder chain here.
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    [[TMPlayer shared] remoteControl:event];
}

@end
