#import "TMLibrary.h"
#import "TMAPIClient.h"
#import "TMLog.h"

NSString *const TMSubscriptionsDidChangeNotification = @"TMSubscriptionsDidChange";
NSString *const TMHistoryDidChangeNotification = @"TMHistoryDidChange";

static NSString *const kSubscribedKey = @"TMSubscribedChannels";

@implementation TMLibrary {
    NSMutableSet *_ids;
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
    }
    return self;
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
        if ([c isKindOfClass:[TMChannel class]] && [c channelID].length) [ids addObject:[c channelID]];
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
