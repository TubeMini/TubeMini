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
/// 360 or 720.
@property (nonatomic, assign) NSInteger preferredQuality;
- (BOOL)isConfigured;
/// "192.168.1.10:8080" → "http://192.168.1.10:8080" (trims, adds scheme, drops trailing "/").
+ (NSString *)normalizeURL:(NSString *)input;
/// Percent-encodes a query value (CFURLCreateStringByAddingPercentEscapes, iOS 6-safe).
+ (NSString *)escape:(NSString *)s;

- (void)getURL:(NSString *)url completion:(TMDataBlock)done;
- (void)feedAtURL:(NSString *)url completion:(TMFeedBlock)done;
/// `path` relative to the server, e.g. `/feeds/api/videos?q=…`.
- (void)feedAtPath:(NSString *)path completion:(TMFeedBlock)done;

- (void)popular:(TMFeedBlock)done;
- (void)searchVideos:(NSString *)query completion:(TMFeedBlock)done;
- (void)searchChannels:(NSString *)query completion:(TMFeedBlock)done;
- (void)related:(NSString *)videoID completion:(TMFeedBlock)done;
- (void)comments:(NSString *)videoID completion:(TMFeedBlock)done;
- (void)uploads:(NSString *)channelID completion:(TMFeedBlock)done;
- (void)video:(NSString *)videoID completion:(void (^)(TMVideo *video, NSString *error))done;
- (void)streams:(NSString *)videoID fresh:(BOOL)fresh completion:(void (^)(TMStreamSet *set, NSString *error))done;
- (void)ping:(void (^)(TMPing *ping, NSString *error))done;

@end
