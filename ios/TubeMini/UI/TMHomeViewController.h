#import <UIKit/UIKit.h>

@class TMListViewController, TMGridViewController;

/// Home tab: the popular feed as a list or a grid ("Danh sách | Lưới" in the navigation bar,
/// remembered in NSUserDefaults), with a refresh button.
@interface TMHomeViewController : UIViewController
@property (nonatomic, readonly) BOOL gridMode;
- (void)setGridMode:(BOOL)grid;
/// The list or grid currently on screen.
- (UIViewController *)activeChild;
@end
