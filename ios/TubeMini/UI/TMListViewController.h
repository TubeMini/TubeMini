#import <UIKit/UIKit.h>
#import "TMAPIClient.h"

/// Loads the first page of a list; later pages follow the feed's `rel='next'` link automatically.
typedef void (^TMFirstPageBlock)(TMFeedBlock done);

/// Generic list of videos / channels / comments with pull-to-refresh, infinite scroll and an
/// error footer (tap to retry). Tapping a video opens it, tapping a channel opens its uploads.
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
@end
