#import <UIKit/UIKit.h>

/// Line icons in the spirit of SF Symbols, drawn with Core Graphics at any size, so the app ships no
/// image assets and the glyphs stay sharp at 1x and 2x. Designed on a 24-point grid.
///
/// Names: home, subs, history, download, settings (each also "<name>.fill" for the selected tab),
/// search, back, chevron.right, chevron.down, refresh, grid, list, play, pause, back15, fwd15, close,
/// headphones, trash, check, plus, globe, key, hd, antenna, moon, wifi, update, paperplane, bolt, info,
/// person.
UIImage *TMIcon(NSString *name, CGFloat size, UIColor *color);
