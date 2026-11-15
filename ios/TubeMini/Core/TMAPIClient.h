#import <Foundation/Foundation.h>
#import "TMModels.h"

/// Callbacks run on the main queue. `error` is a Vietnamese sentence ready to show, nil on success.
typedef void (^TMDataBlock)(NSData *data, NSString *error);
typedef void (^TMFeedBlock)(TMFeed *feed, NSString *error);

/// Talks to tubemini-server: GData feeds for lists, `/tm/v1` for TubeMini features.
/// Settings live in NSUserDefaults (server URL, token, preferred quality).
@interface TMAPIClient : NSObject

+ (instancetype)shared;

/// Normalized server URL without trailing slash ("" when not set yet).
@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, copy) NSString *token;
/// 360, 720 or 1080.
@property (nonatomic, assign) NSInteger preferredQuality;
/// Qualities the user can choose (360, 720, 1080), and the nearest one not above `q`.
+ (NSArray *)qualities;
+ (NSInteger)normalizedQuality:(NSInteger)q;
- (BOOL)isConfigured;
/// "192.168.1.10:8080" → "http://192.168.1.10:8080" (trims, adds scheme, drops trailing "/").
+ (NSString *)normalizeURL:(NSString *)input;
/// Percent-encodes a query value (CFURLCreateStringByAddingPercentEscapes, iOS 6-safe).
+ (NSString *)escape:(NSString *)s;

- (void)getURL:(NSString *)url completion:(TMDataBlock)done;
/// Any method; `form` (string values) is sent as application/x-www-form-urlencoded.
- (void)requestURL:(NSString *)url method:(NSString *)method form:(NSDictionary *)form completion:(TMDataBlock)done;
- (void)feedAtURL:(NSString *)url completion:(TMFeedBlock)done;
/// `path` relative to the server, e.g. `/feeds/api/videos?q=…`.
- (void)feedAtPath:(NSString *)path completion:(TMFeedBlock)done;

- (void)popular:(TMFeedBlock)done;
- (void)searchVideos:(NSString *)query completion:(TMFeedBlock)done;
- (void)searchChannels:(NSString *)query completion:(TMFeedBlock)done;
- (void)related:(NSString *)videoID completion:(TMFeedBlock)done;
- (void)comments:(NSString *)videoID completion:(TMFeedBlock)done;
- (void)uploads:(NSString *)channelID completion:(TMFeedBlock)done;
- (void)channel:(NSString *)channelID completion:(void (^)(TMChannel *channel, NSString *error))done;
- (void)channelPlaylists:(NSString *)channelID completion:(TMFeedBlock)done;
- (void)playlistVideos:(NSString *)playlistID completion:(TMFeedBlock)done;

/// `/tm/v1/subscriptions` (channel feed), subscribe / unsubscribe.
- (void)subscriptions:(TMFeedBlock)done;
- (void)setSubscribed:(BOOL)subscribed channel:(NSString *)channelID completion:(void (^)(NSString *error))done;
/// `/tm/v1/feed`: new videos of the subscribed channels. `fresh` refetches every channel (pull to refresh).
- (void)subscriptionFeed:(BOOL)fresh completion:(TMFeedBlock)done;

/// `/tm/v1/history` (video feed with position / watched).
- (void)history:(TMFeedBlock)done;
/// Saved position of one video (0, 0 when never watched or on error).
- (void)positionOf:(NSString *)videoID completion:(void (^)(NSInteger position, NSInteger duration))done;
- (void)savePosition:(NSInteger)position duration:(NSInteger)duration video:(TMVideo *)video;
/// `videoID` nil = clear the whole history.
- (void)forgetHistory:(NSString *)videoID completion:(void (^)(NSString *error))done;
- (void)video:(NSString *)videoID completion:(void (^)(TMVideo *video, NSString *error))done;
- (void)streams:(NSString *)videoID fresh:(BOOL)fresh completion:(void (^)(TMStreamSet *set, NSString *error))done;
- (void)ping:(void (^)(TMPing *ping, NSString *error))done;

@end
