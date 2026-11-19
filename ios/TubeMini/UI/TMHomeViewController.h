#import <UIKit/UIKit.h>

@class TMListViewController;

/// Home tab: new videos of the subscribed channels ("Đã theo dõi") or the popular feed ("Phổ biến"),
/// picked with chips under the bar, as big cards (YouTube) or compact rows. Both choices are remembered
/// in NSUserDefaults; the first time, Home starts on "Đã theo dõi" only when something is subscribed.
/// Pull to refresh and the refresh button reload the subscribed channels on the server too.
@interface TMHomeViewController : UIViewController
/// YES = big cards, NO = compact rows.
@property (nonatomic, readonly) BOOL gridMode;
- (void)setGridMode:(BOOL)grid;
/// YES = subscriptions feed, NO = popular.
@property (nonatomic, readonly) BOOL subscriptionsSource;
- (void)setSubscriptionsSource:(BOOL)subscriptions;
/// Same as the refresh button.
- (void)refresh;
/// The list on screen.
- (UIViewController *)activeChild;
@end
