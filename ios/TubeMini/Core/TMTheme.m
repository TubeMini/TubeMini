#import "TMTheme.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

NSString *const TMThemeDidChangeNotification = @"TMThemeDidChangeNotification";
static NSString *const kDarkKey = @"TMDarkMode";

static UIColor *rgb(int r, int g, int b) {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
}

@interface TMTheme ()
@property (nonatomic, readwrite) BOOL dark;
@end

/// The image's shape filled with one colour (its alpha is the mask).
static UIImage *tinted(UIImage *image, UIColor *color) {
    if (!image) return nil;
    CGRect r = CGRectMake(0, 0, image.size.width, image.size.height);
    UIGraphicsBeginImageContextWithOptions(r.size, NO, image.scale);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(c, 0, r.size.height);
    CGContextScaleCTM(c, 1, -1);
    CGContextClipToMask(c, r, image.CGImage);
    [color setFill];
    CGContextFillRect(c, r);
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

/// The iPhone "Thêm" (More) list is UIKit's own white table. This stands in front of its data source and
/// recolours each cell for the theme; everything else goes to UIKit's data source.
@interface TMMoreListStyler : NSObject <UITableViewDataSource>
@property (nonatomic, weak) id<UITableViewDataSource> original;
@end

@implementation TMMoreListStyler

- (BOOL)respondsToSelector:(SEL)sel {
    return [super respondsToSelector:sel] || [self.original respondsToSelector:sel];
}

- (id)forwardingTargetForSelector:(SEL)sel {
    return self.original;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.original tableView:tableView numberOfRowsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.original tableView:tableView cellForRowAtIndexPath:indexPath];
    TMTheme *t = [TMTheme current];
    cell.backgroundColor = t.cellBackground;
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = t.text;
    UIView *sel = [[UIView alloc] init];
    sel.backgroundColor = t.selection;
    cell.selectedBackgroundView = sel;
    if (t.dark) cell.imageView.image = tinted(cell.imageView.image, t.secondaryText); // UIKit draws the icons dark grey
    return cell;
}

@end

@implementation TMTheme

+ (TMTheme *)themeDark:(BOOL)dark {
    TMTheme *t = [[TMTheme alloc] init];
    t.dark = dark;
    return t;
}

+ (TMTheme *)current {
    static TMTheme *light, *dark;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        light = [self themeDark:NO];
        dark = [self themeDark:YES];
    });
    return [self isDark] ? dark : light;
}

+ (BOOL)isDark {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDarkKey];
}

+ (void)setDark:(BOOL)dark {
    if (dark == [self isDark]) return;
    [[NSUserDefaults standardUserDefaults] setBool:dark forKey:kDarkKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self applyGlobalAppearance];
    [[NSNotificationCenter defaultCenter] postNotificationName:TMThemeDidChangeNotification object:nil];
}

#pragma mark - Palette

- (UIColor *)background { return self.dark ? rgb(18, 18, 18) : [UIColor whiteColor]; }
- (UIColor *)cellBackground { return self.dark ? rgb(24, 24, 24) : [UIColor whiteColor]; }
- (UIColor *)selection { return self.dark ? rgb(52, 52, 56) : rgb(217, 226, 240); }
- (UIColor *)text { return self.dark ? rgb(236, 236, 236) : [UIColor blackColor]; }
- (UIColor *)secondaryText { return self.dark ? rgb(158, 158, 158) : rgb(85, 85, 85); }
- (UIColor *)separator { return self.dark ? rgb(48, 48, 48) : rgb(214, 214, 214); }
- (UIColor *)placeholder { return self.dark ? rgb(44, 44, 44) : rgb(224, 224, 224); }
- (UIColor *)barTint { return self.dark ? rgb(32, 32, 32) : rgb(158, 20, 20); }
- (UIColor *)tabBarTint { return self.dark ? rgb(14, 14, 14) : rgb(30, 30, 30); }
- (UIColor *)accent { return self.dark ? rgb(255, 92, 92) : rgb(51, 84, 140); }
- (UIColor *)buttonBackground { return self.dark ? rgb(38, 38, 38) : rgb(246, 246, 246); }
- (UIColor *)buttonBorder { return self.dark ? rgb(70, 70, 70) : rgb(190, 190, 190); }
- (UIKeyboardAppearance)keyboard { return self.dark ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault; }

#pragma mark - Helpers

- (void)styleButton:(UIButton *)b {
    b.backgroundColor = self.buttonBackground;
    b.layer.cornerRadius = 8;
    b.layer.borderWidth = 1;
    b.layer.borderColor = self.buttonBorder.CGColor;
    [b setTitleColor:self.accent forState:UIControlStateNormal];
    [b setTitleColor:self.secondaryText forState:UIControlStateHighlighted];
}

- (void)styleSubscribeButton:(UIButton *)b subscribed:(BOOL)subscribed busy:(BOOL)busy {
    [self styleButton:b];
    if (!subscribed) {
        b.backgroundColor = rgb(204, 24, 30);
        b.layer.borderColor = rgb(170, 16, 22).CGColor;
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateHighlighted];
    } else {
        [b setTitleColor:self.secondaryText forState:UIControlStateNormal];
    }
    NSString *title = busy ? @"…" : (subscribed ? @"✓ Đã theo dõi" : @"+ Theo dõi");
    [b setTitle:title forState:UIControlStateNormal];
}

- (void)styleTableView:(UITableView *)tv {
    tv.backgroundView = nil; // grouped tables on iOS 6 iPad draw their own background otherwise
    tv.backgroundColor = self.background;
    tv.separatorColor = self.separator;
}

+ (void)applyGlobalAppearance {
    TMTheme *t = [self current];
    [[UINavigationBar appearance] setTintColor:t.barTint];
    [[UITabBar appearance] setTintColor:t.tabBarTint];
    [[UISearchBar appearance] setTintColor:t.dark ? rgb(40, 40, 40) : rgb(190, 60, 60)];
    [[UISegmentedControl appearance] setTintColor:t.dark ? rgb(70, 70, 70) : rgb(158, 20, 20)];
    [[UIRefreshControl appearance] setTintColor:t.secondaryText];
    // Appearance proxies only affect new views: recolour the bars already on screen
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        [self recolourBarsIn:w.rootViewController theme:t];
    }
}

+ (void)recolourBarsIn:(UIViewController *)vc theme:(TMTheme *)t {
    if (!vc) return;
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabs = (UITabBarController *)vc;
        tabs.tabBar.tintColor = t.tabBarTint;
        for (UIViewController *child in tabs.viewControllers) [self recolourBarsIn:child theme:t];
        [self styleMoreListOf:tabs theme:t];
    } else if ([vc isKindOfClass:[UINavigationController class]]) {
        ((UINavigationController *)vc).navigationBar.tintColor = t.barTint;
    }
    if (vc.presentedViewController) [self recolourBarsIn:vc.presentedViewController theme:t];
}

/// iPhone only (5 tabs fit; the iPad shows all 6): the "Thêm" bar and list in theme colours.
+ (void)styleMoreListOf:(UITabBarController *)tabs theme:(TMTheme *)t {
    if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPhone) return;
    UINavigationController *more = tabs.moreNavigationController;
    more.navigationBar.tintColor = t.barTint;
    UIViewController *list = more.viewControllers.count ? more.viewControllers[0] : nil;
    UITableView *tv = [list.view isKindOfClass:[UITableView class]] ? (UITableView *)list.view : nil;
    if (!tv) return;
    static char kStyler;
    if (!objc_getAssociatedObject(tv, &kStyler)) {
        TMMoreListStyler *styler = [[TMMoreListStyler alloc] init];
        styler.original = tv.dataSource;
        objc_setAssociatedObject(tv, &kStyler, styler, OBJC_ASSOCIATION_RETAIN_NONATOMIC); // dataSource is not retained
        tv.dataSource = styler;
    }
    [t styleTableView:tv];
    [tv reloadData];
}

@end
