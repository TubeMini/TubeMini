#import <UIKit/UIKit.h>

/// One binary runs on iOS 5.0 – 8.x. The deployment target is 5.0, so any newer API is a build error
/// (Makefile: -Werror=unguarded-availability); the few newer things TubeMini wants go through here,
/// looked up at runtime.

/// NSTextAlignment / NSLineBreakMode values. The SDK marks those enums iOS 6+, but UIKit has used the same
/// numbers since iPhone OS 2 (UITextAlignment / UILineBreakMode), so plain numbers work on iOS 5 too.
enum { TMAlignLeft = 0, TMAlignCenter = 1, TMAlignRight = 2 };
enum { TMLineBreakWord = 0, TMLineBreakTail = 4 };

/// iOS 7 or newer: full-screen layout under the status bar, view-controller-based status bar style.
BOOL TMIsIOS7(void);
/// The device is an iPhone / iPod (320 pt wide in portrait).
BOOL TMIsPhone(void);

/// UIStatusBarStyle for the theme on iOS 7+ (light content on dark backgrounds); no-op on iOS 5/6.
void TMSetNeedsStatusBarUpdate(UIViewController *vc);

/// iOS 7+: lists lay out their insets themselves (TMChrome), UIKit must not adjust them.
void TMDisableAutomaticInsets(UIViewController *vc);

/// UILabel shrinks text to fit (minimumScaleFactor on iOS 6+, minimumFontSize on iOS 5).
void TMLabelShrinkToFit(UILabel *label, CGFloat minimumScale);

/// Stretchable image (the edges keep their size, the middle stretches). resizableImageWithCapInsets: tiles
/// the middle instead, and UIImageView on iOS 6 keeps a cache of pre-tiled copies whose keys it can free too
/// early: a later theme change crashed in -[_UIImageViewPretiledImageCacheKey hash] (zombie). Stretching
/// needs no such cache: resizingMode Stretch on iOS 6+, stretchableImage… on iOS 5.
UIImage *TMStretchable(UIImage *image, UIEdgeInsets caps);

/// Font helpers: Helvetica Neue weights exist on iOS 5+, the system font is Helvetica Neue up to iOS 8.
UIFont *TMFontRegular(CGFloat size);
UIFont *TMFontMedium(CGFloat size);
UIFont *TMFontBold(CGFloat size);
