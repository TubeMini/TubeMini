#import <UIKit/UIKit.h>
#import "TMTabBarController.h"

@interface TMAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) TMTabBarController *tabs;
/// Navigation controller of the selected tab.
- (UINavigationController *)nav;
@end
