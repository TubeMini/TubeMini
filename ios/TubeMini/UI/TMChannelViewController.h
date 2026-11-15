#import "TMListViewController.h"

/// Channel page: avatar, name, subscribers, description, Subscribe button, and below it the
/// channel's videos or playlists (segmented control).
@interface TMChannelViewController : TMListViewController
- (instancetype)initWithChannel:(TMChannel *)channel;
/// From a video page, where only the id and name are known; the rest is fetched.
- (instancetype)initWithChannelID:(NSString *)channelID name:(NSString *)name;
@property (nonatomic, readonly) TMChannel *channel;
/// 0 = videos, 1 = playlists.
- (void)showSection:(NSInteger)section;
/// Same as tapping Subscribe / Unsubscribe (debug commands).
- (void)toggleSubscribe;
@end
