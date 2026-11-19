#import <UIKit/UIKit.h>

/// One tab: title under the icon; the selected tab shows "<icon>.fill".
@interface TMTabItem : NSObject
+ (instancetype)itemWithTitle:(NSString *)title icon:(NSString *)icon;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *icon;
@end

/// Root of the app, in place of UITabBarController: the selected tab's navigation controller fills the
/// screen and the tab bar floats over it as a glass capsule near the bottom edge (iOS 26). One tab
/// (`accessoryIndex`, Search) is drawn as a separate round glass button at the right end, the way
/// iOS 26 sets the search tab apart. The "Chỉ nghe" mini player (`accessoryView`) floats just above.
/// Lists keep their last rows clear of the bar with TMAudioBar's applyInsetTo:.
@interface TMTabBarController : UIViewController
@property (nonatomic, copy) NSArray *viewControllers;
/// TMTabItem per view controller.
@property (nonatomic, copy) NSArray *items;
/// Index of the controller shown as the round button at the right; -1 = none.
@property (nonatomic) NSInteger accessoryIndex;
@property (nonatomic) NSUInteger selectedIndex;
@property (nonatomic, readonly) UIViewController *selectedViewController;
/// Floats above the bar, same width as the bar (the mini player); hides itself when idle.
@property (nonatomic, strong) UIView *accessoryView;
/// Points the bar covers at the bottom of the screen (bar + margin under it).
+ (CGFloat)chromeHeight;
@end
