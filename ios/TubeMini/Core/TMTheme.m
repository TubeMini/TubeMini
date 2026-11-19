#import "TMTheme.h"
#import "TMCompat.h"
#import <objc/message.h>

NSString *const TMThemeDidChangeNotification = @"TMThemeDidChangeNotification";
static NSString *const kDarkKey = @"TMDarkMode";

static UIColor *rgb(int r, int g, int b) {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
}

@interface TMTheme ()
@property (nonatomic, readwrite) BOOL dark;
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

- (UIColor *)background { return self.dark ? rgb(15, 15, 15) : [UIColor whiteColor]; }
- (UIColor *)groupedBackground { return self.dark ? rgb(15, 15, 15) : rgb(242, 242, 247); }
- (UIColor *)cellBackground { return self.dark ? rgb(33, 33, 35) : [UIColor whiteColor]; }
- (UIColor *)elevated { return self.dark ? rgb(39, 39, 39) : rgb(242, 242, 242); }
- (UIColor *)elevatedPressed { return self.dark ? rgb(63, 63, 63) : rgb(222, 222, 222); }
- (UIColor *)selection { return self.dark ? rgb(39, 39, 39) : rgb(240, 240, 240); }
- (UIColor *)text { return self.dark ? rgb(241, 241, 241) : rgb(15, 15, 15); }
- (UIColor *)secondaryText { return self.dark ? rgb(170, 170, 170) : rgb(96, 96, 96); }
- (UIColor *)tertiaryText { return self.dark ? rgb(113, 113, 113) : rgb(144, 144, 144); }
- (UIColor *)separator { return self.dark ? rgb(48, 48, 48) : rgb(229, 229, 229); }
- (UIColor *)placeholder { return self.dark ? rgb(39, 39, 39) : rgb(229, 229, 229); }
- (UIColor *)accent { return self.dark ? rgb(10, 145, 255) : rgb(0, 122, 255); }
- (UIColor *)brand { return self.dark ? rgb(255, 64, 72) : rgb(255, 0, 51); }
- (UIColor *)inverse { return self.dark ? rgb(241, 241, 241) : rgb(15, 15, 15); }
- (UIColor *)inverseText { return self.dark ? rgb(15, 15, 15) : [UIColor whiteColor]; }
- (UIColor *)switchOn { return rgb(52, 199, 89); }
- (UIColor *)destructive { return self.dark ? rgb(255, 69, 58) : rgb(255, 56, 60); }
- (UIKeyboardAppearance)keyboard { return self.dark ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault; }
- (UIActivityIndicatorViewStyle)spinnerStyle { return self.dark ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray; }

#pragma mark - Helpers

+ (UIImage *)imageWithColor:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, 1, 1));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return TMStretchable(img, UIEdgeInsetsZero);
}

- (void)styleTableView:(UITableView *)tv {
    tv.backgroundView = nil; // grouped tables on iOS 5/6 draw their own background otherwise
    tv.backgroundColor = self.background;
    tv.separatorStyle = UITableViewCellSeparatorStyleNone;
}

/// Flat bar in the page colour, no hairline, medium title: the iOS 26 top edge. Bar buttons are glass
/// views of their own (TMGlassButton), so the bar's tint only matters for UIKit's own buttons.
+ (void)styleNavigationBar:(UINavigationBar *)bar {
    [self styleNavigationBar:bar color:[self current].background];
}

+ (void)styleNavigationBar:(UINavigationBar *)bar color:(UIColor *)color {
    TMTheme *t = [self current];
    UIImage *bg = [self imageWithColor:color];
    [bar setBackgroundImage:bg forBarMetrics:UIBarMetricsDefault];
    [bar setBackgroundImage:bg forBarMetrics:UIBarMetricsLandscapePhone];
    SEL shadow = NSSelectorFromString(@"setShadowImage:"); // iOS 6+
    if ([bar respondsToSelector:shadow]) ((void (*)(id, SEL, id))objc_msgSend)(bar, shadow, [[UIImage alloc] init]);
    bar.tintColor = TMIsIOS7() ? t.text : (t.dark ? rgb(40, 40, 40) : [UIColor whiteColor]); // iOS 6 iPhone tints the status bar with it
    bar.titleTextAttributes = @{
        UITextAttributeFont : TMFontMedium(17),
        UITextAttributeTextColor : t.text,
        UITextAttributeTextShadowColor : [UIColor clearColor],
        UITextAttributeTextShadowOffset : [NSValue valueWithUIOffset:UIOffsetZero],
    };
}

+ (void)applyGlobalAppearance {
    TMTheme *t = [self current];
    [[UISwitch appearance] setOnTintColor:t.switchOn];
    [[UISegmentedControl appearance] setTintColor:t.dark ? rgb(70, 70, 70) : rgb(120, 120, 128)];
    // Navigation bars: TMNavigationController styles its own (styleNavigationBar:), again on theme changes
}

@end
