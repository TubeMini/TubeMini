#import <UIKit/UIKit.h>

/// Mini player for "Chỉ nghe", floating as a glass panel just above the tab bar on every screen while
/// audio is loaded (iOS 26's tab bar accessory): thumbnail, title, elapsed / total time, −15 s, play /
/// pause, +15 s, close, and a thin seek bar. Tapping the title opens the video page.
@interface TMAudioBar : UIView
+ (CGFloat)height;
/// Called with the video page to open when the title is tapped.
@property (nonatomic, copy) void (^onOpen)(void);
/// Bottom inset that keeps the last rows of a list above the floating tab bar, and above this bar
/// while it is shown.
+ (void)applyInsetTo:(UIScrollView *)scrollView;
@end
