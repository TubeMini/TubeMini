#import <Foundation/Foundation.h>

/// Posted (main thread) after a channel was subscribed / unsubscribed or the list was reloaded.
extern NSString *const TMSubscriptionsDidChangeNotification;
/// Posted (main thread) after a watch position was saved or history entries were removed.
/// userInfo (when about one video): @"videoID", @"position", @"duration" (NSNumber seconds).
extern NSString *const TMHistoryDidChangeNotification;

/// The user's subscriptions as seen by the app: channel ids cached in NSUserDefaults so the
/// Subscribe buttons show the right state at once, synced with `/tm/v1/subscriptions`.
@interface TMLibrary : NSObject
+ (instancetype)shared;
- (BOOL)isSubscribed:(NSString *)channelID;
@property (nonatomic, readonly) NSUInteger subscriptionCount;
/// Reloads the ids from the server (at launch).
- (void)refresh;
/// The subscriptions screen already has the list: take the ids from it.
- (void)updateWithChannels:(NSArray *)channels;
/// Subscribe / unsubscribe on the server, then update the cache and post the notification.
- (void)setSubscribed:(BOOL)subscribed channelID:(NSString *)channelID completion:(void (^)(NSString *error))done;
/// Posts TMHistoryDidChangeNotification.
- (void)historyChangedForVideo:(NSString *)videoID position:(NSInteger)position duration:(NSInteger)duration;

/// Where playback should resume, or 0 to start over: from 10 s until 20 s before the end.
+ (NSInteger)resumePositionFor:(NSInteger)position duration:(NSInteger)duration;
@end
