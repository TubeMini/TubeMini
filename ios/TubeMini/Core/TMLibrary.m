#import "TMLibrary.h"
#import "TMAPIClient.h"
#import "TMLog.h"

NSString *const TMSubscriptionsDidChangeNotification = @"TMSubscriptionsDidChange";
NSString *const TMHistoryDidChangeNotification = @"TMHistoryDidChange";

static NSString *const kSubscribedKey = @"TMSubscribedChannels";
static NSString *const kAvatarsKey = @"TMChannelAvatars";

@implementation TMLibrary {
    NSMutableSet *_ids;
    NSMutableDictionary *_avatars; // channel id -> avatar URL
}

+ (instancetype)shared {
    static TMLibrary *lib;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lib = [[TMLibrary alloc] init]; });
    return lib;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kSubscribedKey];
        _ids = [NSMutableSet setWithArray:saved ?: @[]];
        NSDictionary *avatars = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kAvatarsKey];
        _avatars = [NSMutableDictionary dictionaryWithDictionary:avatars ?: @{}];
    }
    return self;
}

- (NSString *)avatarForChannel:(NSString *)channelID {
    return channelID.length ? _avatars[channelID] : nil;
}

- (void)rememberChannel:(TMChannel *)c {
    if (!c.channelID.length || !c.avatarURL.length || [_avatars[c.channelID] isEqualToString:c.avatarURL]) return;
    if (_avatars.count > 500) [_avatars removeAllObjects]; // a cache, not a library: start over rather than grow
    _avatars[c.channelID] = c.avatarURL;
    [[NSUserDefaults standardUserDefaults] setObject:_avatars forKey:kAvatarsKey];
}

- (BOOL)isSubscribed:(NSString *)channelID {
    return channelID.length && [_ids containsObject:channelID];
}

- (NSUInteger)subscriptionCount {
    return _ids.count;
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:[_ids allObjects] forKey:kSubscribedKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:TMSubscriptionsDidChangeNotification object:self];
}

- (void)updateWithChannels:(NSArray *)channels {
    NSMutableSet *ids = [NSMutableSet set];
    for (id c in channels) {
        if (![c isKindOfClass:[TMChannel class]] || ![c channelID].length) continue;
        [ids addObject:[c channelID]];
        [self rememberChannel:c];
    }
    if ([ids isEqualToSet:_ids]) return;
    _ids = ids;
    [self save];
}

- (void)refresh {
    if (![TMAPIClient shared].isConfigured) return;
    [[TMAPIClient shared] subscriptions:^(TMFeed *feed, NSString *error) {
        if (feed) [self updateWithChannels:feed.entries];
    }];
}

- (void)setSubscribed:(BOOL)subscribed channelID:(NSString *)channelID completion:(void (^)(NSString *))done {
    [[TMAPIClient shared] setSubscribed:subscribed
                                channel:channelID
                             completion:^(NSString *error) {
                                 if (!error) {
                                     if (subscribed) {
                                         [self->_ids addObject:channelID];
                                     } else {
                                         [self->_ids removeObject:channelID];
                                     }
                                     TMLog(@"[library] %@ %@", subscribed ? @"theo dõi" : @"bỏ theo dõi", channelID);
                                     [self save];
                                 }
                                 if (done) done(error);
                             }];
}

- (void)historyChangedForVideo:(NSString *)videoID position:(NSInteger)position duration:(NSInteger)duration {
    NSDictionary *info = videoID.length ? @{ @"videoID" : videoID, @"position" : @(position), @"duration" : @(duration) } : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:TMHistoryDidChangeNotification object:self userInfo:info];
}

+ (NSInteger)resumePositionFor:(NSInteger)position duration:(NSInteger)duration {
    if (position < 10) return 0;
    if (duration > 0 && position >= duration - 20) return 0;
    return position;
}

@end
