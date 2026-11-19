#import "TMListViewController.h"

/// Video page (YouTube layout): rounded thumbnail with a glass Play button, title, views / age, the
/// channel row with its Subscribe pill, a row of action pills (Phát or "Xem tiếp" from the watch history,
/// Chỉ nghe, Tải về, quality), the description in a grey box, and below it the related videos or the
/// comments (segmented control).
@interface TMVideoViewController : TMListViewController
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
/// Downloads at `quality` (360 / 720 / 1080) without the choice sheet (debug commands).
- (void)downloadQuality:(NSInteger)quality;
@end
