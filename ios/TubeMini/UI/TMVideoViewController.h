#import "TMListViewController.h"

/// Video page: big thumbnail with play button, title, channel, views, description, Play (or "Xem tiếp"
/// from the watch history) / quality / channel / subscribe buttons, and below it the related videos or
/// the comments (segmented control).
@interface TMVideoViewController : TMListViewController <UIActionSheetDelegate>
- (instancetype)initWithVideo:(TMVideo *)video;
@property (nonatomic, readonly) TMVideo *video;
/// Same as tapping Play (debug commands).
- (void)play;
/// 0 = related, 1 = comments.
- (void)showSection:(NSInteger)section;
/// Same as tapping Subscribe / Unsubscribe (debug commands).
- (void)toggleSubscribe;
/// Same as tapping "Chỉ nghe" / "Tải về" (debug commands).
- (void)listen;
- (void)download;
@end
