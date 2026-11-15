#import <UIKit/UIKit.h>
#import "TMModels.h"

/// Thumbnail 160×90 with a duration badge, two-line title, "channel · views · age".
@interface TMVideoCell : UITableViewCell
+ (CGFloat)height;
- (void)configureWithVideo:(TMVideo *)video;
@end

/// Avatar, channel name, "subscribers · videos".
@interface TMChannelCell : UITableViewCell
+ (CGFloat)height;
- (void)configureWithChannel:(TMChannel *)channel;
@end

/// Author + age on top, full comment text below (variable height).
@interface TMCommentCell : UITableViewCell
+ (CGFloat)heightForComment:(TMComment *)comment width:(CGFloat)width;
- (void)configureWithComment:(TMComment *)comment;
@end

/// Footer for lists: spinner while loading, or a message (tap to retry).
@interface TMListFooter : UIView
@property (nonatomic, copy) void (^onTap)(void);
- (void)showLoading;
- (void)showMessage:(NSString *)message;
@end
