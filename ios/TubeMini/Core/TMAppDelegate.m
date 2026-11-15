#import "TMAppDelegate.h"
#import "TMHelloViewController.h"
#import "TMLog.h"
#ifdef TM_DEBUG
#import "TMDebug.h"
#endif

@implementation TMAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    TMLog(@"TubeMini %@ khởi động — iOS %@, %@", info[@"CFBundleShortVersionString"],
          [UIDevice currentDevice].systemVersion, TMDeviceModel());

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];
    self.nav = [[UINavigationController alloc] initWithRootViewController:[[TMHelloViewController alloc] init]];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
#ifdef TM_DEBUG
    [TMDebug start];
#endif
    return YES;
}

@end
