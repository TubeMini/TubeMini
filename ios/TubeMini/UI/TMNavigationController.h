#import <UIKit/UIKit.h>

/// Navigation controller with the iOS 26 top edge: a flat bar in the page colour (no hairline), a soft
/// fade where the content scrolls under it, and a round glass back button. Restyles itself when the
/// theme changes; keeps the iOS 7+ edge-swipe back gesture working with the custom back button.
@interface TMNavigationController : UINavigationController <UINavigationControllerDelegate, UIGestureRecognizerDelegate>
@end

/// Screens on the grey grouped background (Settings): the bar takes that colour too.
@protocol TMGroupedScreen
@end

/// Round glass bar button with an icon (TMIcon name).
UIBarButtonItem *TMBarButton(NSString *icon, id target, SEL action);
/// Glass capsule bar button with a title.
UIBarButtonItem *TMBarTextButton(NSString *title, id target, SEL action);
/// A tab's first screen: big bold title at the left of the bar instead of the centred one (YouTube /
/// iOS 26). `logo` = the TubeMini mark before it (Home).
void TMSetLargeTitle(UIViewController *vc, NSString *title, BOOL logo);
