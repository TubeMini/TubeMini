#import <UIKit/UIKit.h>

/// "Đã tải" tab: saved videos for offline viewing, with live progress. Tap a finished one to play it
/// (from where it was left), a failed one to retry, a running one to cancel; swipe left deletes.
@interface TMDownloadsViewController : UITableViewController <UIActionSheetDelegate>
/// Same as tapping row `row` (debug commands).
- (void)selectRow:(NSInteger)row;
@end
