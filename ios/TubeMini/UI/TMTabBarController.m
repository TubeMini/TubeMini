#import "TMTabBarController.h"
#import "TMCompat.h"
#import "TMGlass.h"
#import "TMIcons.h"
#import "TMTheme.h"

@implementation TMTabItem
+ (instancetype)itemWithTitle:(NSString *)title icon:(NSString *)icon {
    TMTabItem *i = [[self alloc] init];
    i.title = title;
    i.icon = icon;
    return i;
}
@end

#pragma mark - Tab button

/// Icon over a small label; the selected one is tinted and shows the filled icon.
@interface TMTabButton : UIControl
@property (nonatomic, strong) TMTabItem *item;
@property (nonatomic) BOOL chosen;
@property (nonatomic) BOOL round; // the search button: icon only
- (void)applyTheme;
@end

@implementation TMTabButton {
    UIImageView *_icon;
    UILabel *_label;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _icon = [[UIImageView alloc] init];
        _icon.contentMode = UIViewContentModeCenter;
        [self addSubview:_icon];
        _label = [[UILabel alloc] init];
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = TMAlignCenter;
        _label.font = TMFontMedium(TMIsPhone() ? 10 : 11);
        TMLabelShrinkToFit(_label, 0.8);
        [self addSubview:_label];
    }
    return self;
}

- (CGFloat)iconSize {
    return self.round ? 24 : (TMIsPhone() ? 25 : 26);
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    UIColor *c = self.chosen ? t.brand : t.text;
    NSString *name = self.item.icon;
    if (self.chosen && !self.round) name = [name stringByAppendingString:@".fill"];
    _icon.image = TMIcon(name, [self iconSize], c);
    _label.text = self.round ? nil : self.item.title;
    _label.textColor = c;
    [self setNeedsLayout];
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self applyTheme];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.55 : 1;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat s = [self iconSize];
    if (self.round) {
        _icon.frame = b;
        _label.frame = CGRectZero;
        return;
    }
    CGFloat labelH = 13, gap = 2, top = floor((b.size.height - s - gap - labelH) / 2);
    _icon.frame = CGRectMake(0, top, b.size.width, s);
    _label.frame = CGRectMake(2, top + s + gap, b.size.width - 4, labelH);
}

@end

#pragma mark - Controller

@implementation TMTabBarController {
    UIView *_bar;             // capsule + round button (everything that floats)
    TMGlassView *_capsule, *_circle, *_lens, *_circleLens;
    NSMutableArray *_buttons; // TMTabButton per item (the accessory one too)
    UIViewController *_shown;
    NSUInteger _selected;
}

+ (CGFloat)barHeight {
    return TMIsPhone() ? 56 : 60;
}

+ (CGFloat)bottomMargin {
    return TMIsPhone() ? 8 : 12;
}

+ (CGFloat)chromeHeight {
    return [self barHeight] + [self bottomMargin];
}

- (instancetype)init {
    if ((self = [super init])) {
        _accessoryIndex = -1;
        _buttons = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// iOS 5 only resizes the root view on rotation when it has flexible width / height (iOS 6+ sets its frame anyway)
- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [TMTheme current].background;
    _bar = [[UIView alloc] init];
    _bar.backgroundColor = [UIColor clearColor];
    _capsule = [[TMGlassView alloc] initWithStyle:TMGlassStyleBar radius:-1];
    _circle = [[TMGlassView alloc] initWithStyle:TMGlassStyleBar radius:-1];
    _lens = [[TMGlassView alloc] initWithStyle:TMGlassStyleLens radius:-1];
    _circleLens = [[TMGlassView alloc] initWithStyle:TMGlassStyleLens radius:-1];
    [_bar addSubview:_capsule];
    [_bar addSubview:_circle];
    [_bar addSubview:_lens];
    [_bar addSubview:_circleLens];
    [self.view addSubview:_bar];
    [self rebuildButtons];
    if (_accessoryView) [self.view addSubview:_accessoryView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [self showSelected];
    [self themeChanged];
}

- (void)themeChanged {
    self.view.backgroundColor = [TMTheme current].background;
    for (TMTabButton *b in _buttons) [b applyTheme];
    [self updateStatusBar];
}

- (void)updateStatusBar {
    if (TMIsIOS7()) {
        TMSetNeedsStatusBarUpdate(self);
    }
    // iOS 5/6: the black status bar of Info.plist in both themes (iOS 6 tints a light one only for a
    // UINavigationController / UITabBarController root, otherwise it is the old grey gradient)
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return [TMTheme isDark] ? (UIStatusBarStyle)1 /* light content, iOS 7+ */ : UIStatusBarStyleDefault;
}

#pragma mark - Rotation (all orientations, iOS 5 and 6+)

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return YES;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - Tabs

- (void)setViewControllers:(NSArray *)viewControllers {
    _viewControllers = [viewControllers copy];
    if (self.isViewLoaded) {
        [self rebuildButtons];
        [self showSelected];
    }
}

- (void)setItems:(NSArray *)items {
    _items = [items copy];
    if (self.isViewLoaded) [self rebuildButtons];
}

- (void)setAccessoryView:(UIView *)accessoryView {
    [_accessoryView removeFromSuperview];
    _accessoryView = accessoryView;
    if (self.isViewLoaded && accessoryView) {
        [self.view addSubview:accessoryView];
        [self.view setNeedsLayout];
    }
}

- (void)rebuildButtons {
    for (UIView *b in _buttons) [b removeFromSuperview];
    [_buttons removeAllObjects];
    for (NSUInteger i = 0; i < _items.count; i++) {
        TMTabButton *b = [[TMTabButton alloc] initWithFrame:CGRectZero];
        b.item = _items[i];
        b.round = (NSInteger)i == _accessoryIndex;
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_bar addSubview:b];
        [_buttons addObject:b];
    }
    [self updateButtons];
    [self.view setNeedsLayout];
}

- (UIViewController *)selectedViewController {
    return _selected < _viewControllers.count ? _viewControllers[_selected] : nil;
}

- (NSUInteger)selectedIndex {
    return _selected;
}

- (void)setSelectedIndex:(NSUInteger)index {
    if (index >= _viewControllers.count) return;
    _selected = index;
    if (self.isViewLoaded) {
        [self showSelected];
        [UIView animateWithDuration:0.25
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ [self layoutBar]; }
                         completion:nil];
    }
}

- (void)tabTapped:(TMTabButton *)b {
    NSUInteger i = (NSUInteger)b.tag;
    if (i == _selected) {
        // Again on the current tab: back to its first screen, or to the top of it
        UINavigationController *nav = [self.selectedViewController isKindOfClass:[UINavigationController class]]
                                          ? (UINavigationController *)self.selectedViewController
                                          : nil;
        if (nav.viewControllers.count > 1) {
            [nav popToRootViewControllerAnimated:YES];
        } else {
            [self scrollToTop:nav.topViewController.view];
        }
        return;
    }
    self.selectedIndex = i;
}

- (BOOL)scrollToTop:(UIView *)v {
    if ([v isKindOfClass:[UIScrollView class]] && ((UIScrollView *)v).scrollsToTop) {
        UIScrollView *sv = (UIScrollView *)v;
        [sv setContentOffset:CGPointMake(0, -sv.contentInset.top) animated:YES];
        return YES;
    }
    for (UIView *s in v.subviews) {
        if ([self scrollToTop:s]) return YES;
    }
    return NO;
}

- (void)updateButtons {
    for (TMTabButton *b in _buttons) b.chosen = (NSUInteger)b.tag == _selected;
}

- (void)showSelected {
    UIViewController *vc = self.selectedViewController;
    [self updateButtons];
    if (!vc || vc == _shown) return;
    if (_shown) {
        [_shown willMoveToParentViewController:nil];
        [_shown.view removeFromSuperview];
        [_shown removeFromParentViewController];
    }
    _shown = vc;
    [self addChildViewController:vc];
    vc.view.frame = self.view.bounds;
    vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:vc.view atIndex:0];
    [vc didMoveToParentViewController:self];
}

#pragma mark - Layout

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    _shown.view.frame = self.view.bounds;
    [self layoutBar]; // the tab's view sits at index 0, under the bars; alerts are added above them
}

/// Capsule with the tabs + a round button of the same height, centred as one group.
- (void)layoutBar {
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    CGFloat h = [TMTabBarController barHeight], gap = 8;
    BOOL round = _accessoryIndex >= 0 && (NSUInteger)_accessoryIndex < _buttons.count;
    NSUInteger tabs = _buttons.count - (round ? 1 : 0);
    CGFloat side = TMIsPhone() ? 12 : 20;
    CGFloat capsuleW = W - 2 * side - (round ? h + gap : 0);
    if (!TMIsPhone()) capsuleW = MIN(capsuleW, tabs * 104 + 12);
    CGFloat groupW = capsuleW + (round ? gap + h : 0);
    CGFloat x0 = floor((W - groupW) / 2), y = H - [TMTabBarController bottomMargin] - h;
    _bar.frame = CGRectMake(x0, y, groupW, h);
    _capsule.frame = CGRectMake(0, 0, capsuleW, h);
    _circle.hidden = !round;
    _circle.frame = CGRectMake(capsuleW + gap, 0, h, h);

    CGFloat inset = 4, itemW = (capsuleW - 2 * inset) / MAX(tabs, 1u);
    NSUInteger slot = 0;
    for (TMTabButton *b in _buttons) {
        if (b.round) {
            b.frame = _circle.frame;
            continue;
        }
        b.frame = CGRectMake(inset + floor(slot * itemW), 0, floor(itemW), h);
        slot++;
    }
    TMTabButton *sel = _selected < _buttons.count ? _buttons[_selected] : nil;
    BOOL roundSelected = sel.round;
    _lens.hidden = !sel || roundSelected;
    _circleLens.hidden = !roundSelected;
    if (sel && !roundSelected) _lens.frame = CGRectInset(sel.frame, 0, inset);
    _circleLens.frame = CGRectInset(_circle.frame, inset, inset);

    if (_accessoryView) {
        CGFloat ah = _accessoryView.bounds.size.height;
        _accessoryView.frame = CGRectMake(x0, y - gap - ah, groupW, ah);
    }
}

@end
