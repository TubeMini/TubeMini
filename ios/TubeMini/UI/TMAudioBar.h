#import <UIKit/UIKit.h>

/// Mini player for "Chỉ nghe", docked above the tab bar on every screen while audio is loaded:
/// a seek bar, thumbnail, title, elapsed / total time, −15 s, play / pause, +15 s, close. Tapping the
/// title opens the video page. Lives on the tab bar controller's view (which rotates on iOS 6).
@interface TMAudioBar : UIView
+ (CGFloat)height;
/// Called with the video page to open when the title is tapped.
@property (nonatomic, copy) void (^onOpen)(void);
/// Bottom inset so the last rows of a list can scroll above the bar while it is shown.
+ (void)applyInsetTo:(UIScrollView *)scrollView;
@end
