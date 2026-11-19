#import "TMNavigationController.h"
#import "TMCompat.h"
#import "TMGlass.h"
#import "TMTheme.h"

#pragma mark - Bar items

UIBarButtonItem *TMBarButton(NSString *icon, id target, SEL action) {
    return [[UIBarButtonItem alloc] initWithCustomView:[TMGlassButton buttonWithIcon:icon target:target action:action]];
}

UIBarButtonItem *TMBarTextButton(NSString *title, id target, SEL action) {
    return [[UIBarButtonItem alloc] initWithCustomView:[TMGlassButton buttonWithTitle:title target:target action:action]];
}

/// "TubeMini" / tab name in bold at the left of the bar, optionally after the logo.
@interface TMLargeTitleView : UIView
- (instancetype)initWithTitle:(NSString *)title logo:(BOOL)logo;
@end

@implementation TMLargeTitleView {
    UILabel *_label;
    UIImageView *_logo;
}

- (instancetype)initWithTitle:(NSString *)title logo:(BOOL)logo {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [UIColor clearColor];
        _label = [[UILabel alloc] init];
        _label.backgroundColor = [UIColor clearColor];
        _label.font = TMFontBold(TMIsPhone() ? 22 : 24);
        _label.text = title;
        [self addSubview:_label];
        if (logo) {
            _logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LogoMark.png"]];
            [self addSubview:_logo];
        }
        CGSize s = [title sizeWithFont:_label.font];
        CGFloat lx = logo ? 30 + 7 : 0;
        _logo.frame = CGRectMake(0, 7, 30, 30);
        _label.frame = CGRectMake(lx, 0, ceil(s.width), 44);
        self.frame = CGRectMake(0, 0, lx + ceil(s.width) + (TMIsIOS7() ? 0 : 6), 44);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyTheme)
                                                     name:TMThemeDidChangeNotification
                                                   object:nil];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    _label.textColor = [TMTheme current].text;
}

@end

void TMSetLargeTitle(UIViewController *vc, NSString *title, BOOL logo) {
    vc.title = title;
    TMLargeTitleView *v = [[TMLargeTitleView alloc] initWithTitle:title logo:logo];
    // iOS 5/6 put a custom left view 5 pt from the edge, iOS 7+ 16 pt: nudge the old ones in a little
    if (!TMIsIOS7()) {
        UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, v.bounds.size.width + 8, 44)];
        v.frame = CGRectOffset(v.bounds, 8, 0);
        [box addSubview:v];
        vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:box];
    } else {
        vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:v];
    }
    vc.navigationItem.titleView = [[UIView alloc] initWithFrame:CGRectZero]; // no centred title
}

#pragma mark - Navigation controller

@implementation TMNavigationController {
    UIImageView *_fade;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;
    _fade = [[UIImageView alloc] init];
    _fade.userInteractionEnabled = NO;
    [self.view addSubview:_fade];
    SEL pop = NSSelectorFromString(@"interactivePopGestureRecognizer"); // iOS 7+
    if ([self respondsToSelector:pop]) {
        UIGestureRecognizer *g = [self valueForKey:@"interactivePopGestureRecognizer"];
        g.delegate = self;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [self applyTheme];
    for (UIViewController *vc in self.viewControllers) [self prepare:vc root:vc == self.viewControllers[0]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIColor *)pageColor {
    TMTheme *t = [TMTheme current];
    return [self.topViewController conformsToProtocol:@protocol(TMGroupedScreen)] ? t.groupedBackground : t.background;
}

- (void)applyTheme {
    UIColor *page = [self pageColor];
    [TMTheme styleNavigationBar:self.navigationBar color:page];
    self.view.backgroundColor = page;
    _fade.image = [self fadeImage:page];
}

/// Page colour fading out downwards: the soft scroll edge under the bar.
- (UIImage *)fadeImage:(UIColor *)bg {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 12), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (__bridge id)[bg colorWithAlphaComponent:0.9].CGColor, (__bridge id)[bg colorWithAlphaComponent:0].CGColor ];
    CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(0, 12), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(space);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bar = self.navigationBar.frame;
    _fade.hidden = self.navigationBarHidden;
    _fade.frame = CGRectMake(0, CGRectGetMaxY(bar), self.view.bounds.size.width, 12);
    [self.view bringSubviewToFront:_fade];
}

/// Every screen: no automatic insets (iOS 7+), no title on UIKit's own back button, and a round glass
/// back button on pushed ones. Set before the push: iOS 7+ builds the bar items during the push.
- (void)prepare:(UIViewController *)vc root:(BOOL)root {
    TMDisableAutomaticInsets(vc);
    if (!vc.navigationItem.backBarButtonItem) {
        vc.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    }
    if (root || vc.navigationItem.leftBarButtonItem) return;
    vc.navigationItem.hidesBackButton = YES;
    vc.navigationItem.leftBarButtonItem = TMBarButton(@"back", self, @selector(back));
}

- (void)back {
    [self popViewControllerAnimated:YES];
}

- (void)pushViewController:(UIViewController *)vc animated:(BOOL)animated {
    [self prepare:vc root:self.viewControllers.count == 0];
    [super pushViewController:vc animated:animated];
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    [self prepare:vc root:self.viewControllers.count && vc == self.viewControllers[0]];
    if (self.isViewLoaded) [self applyTheme]; // grouped screens have another page colour
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return self.viewControllers.count > 1;
}

@end
