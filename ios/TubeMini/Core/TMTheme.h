#import <UIKit/UIKit.h>

/// Posted (main thread) after the theme changes; screens refresh their colours.
extern NSString *const TMThemeDidChangeNotification;

/// App colour theme. iOS 6 has no system dark mode, so TubeMini keeps its own light / dark palette,
/// persisted in NSUserDefaults. Screens read colours from `[TMTheme current]` when they lay out or
/// configure cells, and listen for TMThemeDidChangeNotification.
@interface TMTheme : NSObject
+ (TMTheme *)current;
+ (BOOL)isDark;
/// Saves, re-applies the bar appearance and posts TMThemeDidChangeNotification.
+ (void)setDark:(BOOL)dark;
/// Applies appearance proxies and recolours bars already on screen (call once at launch too).
+ (void)applyGlobalAppearance;

@property (nonatomic, readonly) BOOL dark;
@property (nonatomic, readonly) UIColor *background;      // lists, pages
@property (nonatomic, readonly) UIColor *cellBackground;
@property (nonatomic, readonly) UIColor *selection;       // highlighted row / cell
@property (nonatomic, readonly) UIColor *text;
@property (nonatomic, readonly) UIColor *secondaryText;
@property (nonatomic, readonly) UIColor *separator;
@property (nonatomic, readonly) UIColor *placeholder;     // image placeholders
@property (nonatomic, readonly) UIColor *barTint;         // navigation bar
@property (nonatomic, readonly) UIColor *tabBarTint;
@property (nonatomic, readonly) UIColor *accent;          // buttons, links
@property (nonatomic, readonly) UIColor *buttonBackground;
@property (nonatomic, readonly) UIColor *buttonBorder;
@property (nonatomic, readonly) UIKeyboardAppearance keyboard;

/// Rounded button in theme colours (iOS 6 rounded-rect buttons are always white).
- (void)styleButton:(UIButton *)button;
/// Background / separators / cells of a table view.
- (void)styleTableView:(UITableView *)tableView;
@end
