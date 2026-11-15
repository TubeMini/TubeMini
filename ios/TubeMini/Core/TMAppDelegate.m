#import "TMAppDelegate.h"
#import "TMAPIClient.h"
#import "TMImageLoader.h"
#import "TMHomeViewController.h"
#import "TMListViewController.h"
#import "TMLog.h"
#import "TMSearchViewController.h"
#import "TMSettingsViewController.h"
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
        [self wrap:[[TMSettingsViewController alloc] init] title:@"Cài đặt" image:settingsIcon],
    ];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [TMTheme current].background;
    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];

    if (![TMAPIClient shared].isConfigured) {
        self.tabs.selectedIndex = 2;
        [[[UIAlertView alloc] initWithTitle:@"Chào mừng đến TubeMini"
                                    message:@"Nhập địa chỉ máy chủ tubemini-server trong mạng nhà để bắt đầu."
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    }
#ifdef TM_DEBUG
    [TMDebug start];
#endif
    return YES;
}

@end
