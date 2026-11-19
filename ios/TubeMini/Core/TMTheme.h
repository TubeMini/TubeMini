#import <UIKit/UIKit.h>

/// Posted (main thread) after the theme changes; screens refresh their colours.
extern NSString *const TMThemeDidChangeNotification;

/// App colour theme, iOS 26 / YouTube style ("Liquid Glass" bars over white or near-black pages).
/// iOS 5–8 have no system dark mode, so TubeMini keeps its own light / dark palette, persisted in
/// NSUserDefaults. Screens read colours from `[TMTheme current]` when they lay out or configure cells,
/// and listen for TMThemeDidChangeNotification.
@interface TMTheme : NSObject
+ (TMTheme *)current;
+ (BOOL)isDark;
/// Saves, re-applies the bar appearance and posts TMThemeDidChangeNotification.
+ (void)setDark:(BOOL)dark;
/// Appearance proxies (call once at launch, before any bar is created).
+ (void)applyGlobalAppearance;

@property (nonatomic, readonly) BOOL dark;
@property (nonatomic, readonly) UIColor *background;        // pages, lists, bars
@property (nonatomic, readonly) UIColor *groupedBackground; // behind the cards of Settings
@property (nonatomic, readonly) UIColor *cellBackground;    // cards (Settings rows, sheets)
@property (nonatomic, readonly) UIColor *elevated;          // chips, pills, description box, text fields
@property (nonatomic, readonly) UIColor *elevatedPressed;
@property (nonatomic, readonly) UIColor *selection;         // highlighted row / tile
@property (nonatomic, readonly) UIColor *text;
@property (nonatomic, readonly) UIColor *secondaryText;
@property (nonatomic, readonly) UIColor *tertiaryText;
@property (nonatomic, readonly) UIColor *separator;
@property (nonatomic, readonly) UIColor *placeholder;       // image placeholders
@property (nonatomic, readonly) UIColor *accent;            // links, text buttons (iOS 26 blue)
@property (nonatomic, readonly) UIColor *brand;             // TubeMini red: selected tab, progress, Play
@property (nonatomic, readonly) UIColor *inverse;           // "Theo dõi" button: black on light, white on dark
@property (nonatomic, readonly) UIColor *inverseText;
@property (nonatomic, readonly) UIColor *switchOn;
@property (nonatomic, readonly) UIColor *destructive;
@property (nonatomic, readonly) UIKeyboardAppearance keyboard;
@property (nonatomic, readonly) UIActivityIndicatorViewStyle spinnerStyle;

/// 1×1 stretchable image of a colour (bar backgrounds).
+ (UIImage *)imageWithColor:(UIColor *)color;
/// Flat bar in the page colour, no hairline, medium title (the iOS 26 top edge).
+ (void)styleNavigationBar:(UINavigationBar *)bar;
/// Same, in another page colour (grouped screens).
+ (void)styleNavigationBar:(UINavigationBar *)bar color:(UIColor *)color;
/// Background / separators of a table view (TubeMini draws no separators: rows are spaced instead).
- (void)styleTableView:(UITableView *)tableView;
@end
