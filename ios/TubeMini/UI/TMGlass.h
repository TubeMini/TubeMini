#import <UIKit/UIKit.h>

/// iOS 26 "Liquid Glass" look-alikes that run on iOS 5–8. Real-time blur is not an option there (no
/// UIVisualEffectView before iOS 8, and the A4 / A5 GPUs of the iPad 1 / iPad mini 1 get no blur even on
/// iOS 8), so the glass is drawn once into stretchable images: a translucent fill, a gloss on the upper
/// half, a light rim that fades downwards, a hairline edge and a soft shadow. Every control re-reads the
/// theme on TMThemeDidChangeNotification.

typedef NS_ENUM(NSInteger, TMGlassStyle) {
    TMGlassStyleBar,    // floating bars: tab bar, mini player
    TMGlassStyleButton, // round buttons in the top bar, play button over the thumbnail
    TMGlassStyleLens,   // the selected tab's highlight inside the bar
    TMGlassStylePanel,  // alerts and sheets
};

/// Stretchable glass image; `radius` is the corner radius of the shape, the image has TMGlassPad()
/// points of shadow room on each side.
UIImage *TMGlassImage(TMGlassStyle style, CGFloat radius, BOOL pressed);
CGFloat TMGlassPad(TMGlassStyle style);
/// Stretchable rounded rectangle in one colour (cards, pills, chips); radius = height / 2 for a capsule.
UIImage *TMRoundImage(UIColor *fill, CGFloat radius);

/// A glass shape that fills the view's bounds (the shadow spills outside).
@interface TMGlassView : UIView
/// `radius` < 0: capsule (half the height).
- (instancetype)initWithStyle:(TMGlassStyle)style radius:(CGFloat)radius;
@property (nonatomic) TMGlassStyle style;
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL pressed;
@end

/// Round glass button with an icon (44 × 44 touch area, 36 pt glass circle), or a glass capsule with a
/// title, for the top bar and overlays.
@interface TMGlassButton : UIButton
+ (instancetype)buttonWithIcon:(NSString *)icon target:(id)target action:(SEL)action;
+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic) CGFloat iconSize;
/// Space between the frame and the glass (default 4).
@property (nonatomic) CGFloat glassInset;
/// Icon / title colour; nil = the theme's text colour.
@property (nonatomic, strong) UIColor *tint;
- (void)applyTheme;
@end

typedef NS_ENUM(NSInteger, TMPillStyle) {
    TMPillStyleGray,    // YouTube's grey action pills
    TMPillStyleBrand,   // red, white text (Play)
    TMPillStyleInverse, // black on light / white on dark ("Theo dõi")
};

/// Filled capsule button with an optional icon before the title (36 pt high by default).
@interface TMPill : UIButton
+ (instancetype)pillWithTitle:(NSString *)title icon:(NSString *)icon style:(TMPillStyle)style target:(id)target action:(SEL)action;
@property (nonatomic) TMPillStyle pillStyle;
@property (nonatomic, copy) NSString *iconName;
/// Width that fits the icon and title.
- (CGFloat)fittingWidth;
- (void)setTitle:(NSString *)title; // normal state
- (void)applyTheme;
@end

/// Horizontal row of capsule chips (YouTube's filter chips); the selected one is inverted.
@interface TMChipBar : UIScrollView
@property (nonatomic, copy) NSArray *titles;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
- (void)applyTheme;
@end

/// iOS 26 segmented control: a capsule track with a sliding raised thumb. Sends ValueChanged.
@interface TMSegmentedControl : UIControl
- (instancetype)initWithItems:(NSArray *)titles;
@property (nonatomic) NSInteger selectedSegmentIndex;
@property (nonatomic, readonly) NSUInteger numberOfSegments;
- (void)applyTheme;
@end

/// iOS 26 switch: wide capsule track, pill knob, green when on. Sends ValueChanged.
@interface TMSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
- (void)applyTheme;
@end

/// Pull-to-refresh for any scroll view, iOS 5 included (UIRefreshControl is iOS 6+ and table-only).
/// The owner forwards the two scroll callbacks.
@interface TMRefreshControl : UIView
- (instancetype)initWithScrollView:(UIScrollView *)scrollView;
@property (nonatomic, copy) void (^onRefresh)(void);
@property (nonatomic, readonly) BOOL refreshing;
- (void)scrollViewDidScroll;
- (void)scrollViewDidEndDragging;
- (void)endRefreshing;
- (void)applyTheme;
@end

/// Text field whose placeholder follows the theme (secondary text colour).
@interface TMTextField : UITextField
@end

/// Thin capsule track, small white knob (the mini player's seek bar).
void TMStyleSlider(UISlider *slider, UIColor *fill);
