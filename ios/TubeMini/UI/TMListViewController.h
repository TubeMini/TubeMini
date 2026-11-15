#import <UIKit/UIKit.h>
#import "TMAPIClient.h"

/// Loads the first page of a list; later pages follow the feed's `rel='next'` link automatically.
typedef void (^TMFirstPageBlock)(TMFeedBlock done);

/// Generic list of videos / channels / comments / playlists with pull-to-refresh, infinite scroll and
/// an error footer (tap to retry). Tapping a video opens it, a channel opens the channel page, a
/// playlist opens its videos.
@interface TMListViewController : UITableViewController
- (instancetype)initWithTitle:(NSString *)title firstPage:(TMFirstPageBlock)firstPage;
@property (nonatomic, copy) TMFirstPageBlock firstPage;
/// Shown when the first page is empty.
@property (nonatomic, copy) NSString *emptyMessage;
@property (nonatomic, readonly) NSArray *items;
- (void)reload;
/// Same as tapping row `row` (used by debug commands).
- (void)selectRow:(NSInteger)row;
/// Shows a message in the footer without loading (e.g. "type to search").
- (void)showIdleMessage:(NSString *)message;
/// Set to allow swipe-to-delete: the row disappears, then this runs with the removed item.
@property (nonatomic, copy) void (^onDelete)(id item);
/// Title of the swipe-to-delete button (default "Xoá").
@property (nonatomic, copy) NSString *deleteTitle;
/// Runs when the user pulls to refresh, before the reload.
@property (nonatomic, copy) void (^willRefresh)(void);
/// Same as swiping row `row` away (debug commands).
- (void)deleteRow:(NSInteger)row;
/// Re-applies theme colours; subclasses extend it (called on TMThemeDidChangeNotification, then reloadData).
- (void)applyTheme;
@end
