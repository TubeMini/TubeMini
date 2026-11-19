#import <UIKit/UIKit.h>
#import "TMModels.h"

/// Side margin of lists: 12 pt on an iPhone, 20 pt on the iPad.
CGFloat TMListMargin(void);
/// Round avatar with the channel's first letter on a colour picked from the name (YouTube's default
/// avatar), for channels whose picture is not known.
UIImage *TMLetterAvatar(NSString *name, CGFloat size);

/// Compact row: rounded thumbnail with a duration badge, two-line title, "channel · views · age".
/// History entries get a progress capsule inside the thumbnail and "Đã xem …" instead of views / age.
@interface TMVideoCell : UITableViewCell
+ (CGFloat)height;
- (void)configureWithVideo:(TMVideo *)video;
/// Own meta line and bar (0–1, 0 = none): download rows.
- (void)configureWithVideo:(TMVideo *)video meta:(NSString *)meta progress:(CGFloat)progress;
/// Playlist row: first video's thumbnail, title, "N video".
- (void)configureWithPlaylist:(TMPlaylist *)playlist;
@end

/// One row of YouTube-style video cards: big rounded thumbnail, channel avatar, title, meta. 1 column on
/// an iPhone in portrait, 2 on wider screens, 3 on the iPad in landscape.
@interface TMVideoCardRow : UITableViewCell
+ (NSInteger)columnsForWidth:(CGFloat)width;
+ (CGFloat)heightForWidth:(CGFloat)width;
/// Videos of this row (at most `columns`); `first` = index of the first one in the list.
- (void)configureWithVideos:(NSArray *)videos first:(NSInteger)first width:(CGFloat)width;
/// Called with the list index of the tapped card.
@property (nonatomic, copy) void (^onTap)(NSInteger index);
@end

/// Avatar, channel name, "subscribers · videos", chevron.
@interface TMChannelCell : UITableViewCell
+ (CGFloat)height;
- (void)configureWithChannel:(TMChannel *)channel;
@end

/// Letter avatar, author + age, full comment text below (variable height).
@interface TMCommentCell : UITableViewCell
+ (CGFloat)heightForComment:(TMComment *)comment width:(CGFloat)width;
- (void)configureWithComment:(TMComment *)comment;
@end

/// Footer for lists: spinner while loading, or a message (tap to retry).
@interface TMListFooter : UIView
@property (nonatomic, copy) void (^onTap)(void);
- (void)showLoading;
- (void)showMessage:(NSString *)message;
/// Re-reads the theme colours.
- (void)applyTheme;
@end
