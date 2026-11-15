#import "TMAPIClient.h"
#import "TMAtomParser.h"
#import "TMExtParser.h"
#import "TMLog.h"
#import <UIKit/UIKit.h>

static NSString *const kServerKey = @"TMServerURL";
static NSString *const kTokenKey = @"TMToken";
static NSString *const kQualityKey = @"TMQuality";
static const NSTimeInterval kTimeout = 20;

@implementation TMAPIClient {
    NSOperationQueue *_queue;
}

+ (instancetype)shared {
    static TMAPIClient *client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ client = [[TMAPIClient alloc] init]; });
    return client;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 4;
    }
    return self;
}

#pragma mark - Settings

- (NSString *)serverURL {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kServerKey] ?: @"";
}

- (void)setServerURL:(NSString *)serverURL {
    [[NSUserDefaults standardUserDefaults] setObject:[TMAPIClient normalizeURL:serverURL] forKey:kServerKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)token {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kTokenKey] ?: @"";
}

- (void)setToken:(NSString *)token {
    NSString *t = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:t forKey:kTokenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray *)qualities {
    return @[ @360, @720, @1080 ];
}

+ (NSInteger)normalizedQuality:(NSInteger)q {
    return q >= 1080 ? 1080 : (q >= 720 ? 720 : 360);
}

- (NSInteger)preferredQuality {
    return [TMAPIClient normalizedQuality:[[NSUserDefaults standardUserDefaults] integerForKey:kQualityKey]];
}

- (void)setPreferredQuality:(NSInteger)preferredQuality {
    [[NSUserDefaults standardUserDefaults] setInteger:[TMAPIClient normalizedQuality:preferredQuality] forKey:kQualityKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isConfigured {
    return self.serverURL.length > 0;
}

+ (NSString *)normalizeURL:(NSString *)input {
    NSString *s = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (!s.length) return @"";
    if ([s rangeOfString:@"://"].location == NSNotFound) s = [@"http://" stringByAppendingString:s];
    while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}

+ (NSString *)escape:(NSString *)s {
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(
        NULL, (__bridge CFStringRef)(s ?: @""), NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8);
    return CFBridgingRelease(escaped);
}

#pragma mark - HTTP

/// Vietnamese sentence for a network error.
- (NSString *)messageForError:(NSError *)err {
    switch (err.code) {
    case NSURLErrorTimedOut:
        return @"Máy chủ không phản hồi (quá 20 giây). Thử lại sau.";
    case NSURLErrorNotConnectedToInternet:
        return @"iPad chưa kết nối mạng. Kiểm tra Wi-Fi.";
    case NSURLErrorCannotFindHost:
    case NSURLErrorCannotConnectToHost:
    case NSURLErrorNetworkConnectionLost:
    case NSURLErrorDNSLookupFailed:
        return [NSString stringWithFormat:@"Không kết nối được tới máy chủ %@. Kiểm tra địa chỉ trong Cài đặt và máy chủ có "
                                          @"đang chạy không.",
                                          self.serverURL];
    case NSURLErrorBadURL:
    case NSURLErrorUnsupportedURL:
        return @"Địa chỉ máy chủ không hợp lệ. Sửa lại trong Cài đặt.";
    default:
        return [NSString stringWithFormat:@"Lỗi mạng (%ld). Thử lại sau.", (long)err.code];
    }
}

- (NSString *)messageForStatus:(NSInteger)status data:(NSData *)data {
    NSString *tm = [TMExtParser errorMessageIn:data];
    if (tm) return tm;
    if (status == 401) return @"Sai hoặc thiếu mã truy cập. Kiểm tra Cài đặt.";
    if (status == 404) return @"Không tìm thấy (máy chủ không có dữ liệu này).";
    if (status >= 500) return [NSString stringWithFormat:@"Máy chủ gặp lỗi (mã %ld). Thử lại sau.", (long)status];
    return [NSString stringWithFormat:@"Máy chủ trả lỗi %ld.", (long)status];
}

- (void)getURL:(NSString *)url completion:(TMDataBlock)done {
    if (!self.isConfigured) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"Chưa nhập địa chỉ máy chủ. Vào Cài đặt để nhập."); });
        return;
    }
    NSURL *u = [NSURL URLWithString:url];
    if (!u) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"Địa chỉ máy chủ không hợp lệ. Sửa lại trong Cài đặt."); });
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:kTimeout];
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    [req setValue:[NSString stringWithFormat:@"TubeMini/%@ (iPad; iOS %@)", version, [UIDevice currentDevice].systemVersion]
        forHTTPHeaderField:@"User-Agent"];
    if (self.token.length) [req setValue:self.token forHTTPHeaderField:@"X-Auth-Token"];
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:_queue
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
                               NSString *message = nil;
                               NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]]
                                                      ? ((NSHTTPURLResponse *)resp).statusCode
                                                      : 0;
                               if (err) {
                                   message = [self messageForError:err];
                               } else if (status >= 400) {
                                   message = [self messageForStatus:status data:data];
                               }
                               if (message) TMLog(@"[api] %@ → %@", u.path, message);
                               dispatch_async(dispatch_get_main_queue(), ^{ done(message ? nil : data, message); });
                           }];
}

- (void)feedAtURL:(NSString *)url completion:(TMFeedBlock)done {
    [self getURL:url
        completion:^(NSData *data, NSString *error) {
            if (error) {
                done(nil, error);
                return;
            }
            // Parse off the main thread: feeds are 20–50 KB of XML
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                TMFeed *feed = [TMAtomParser parseFeed:data];
                dispatch_async(dispatch_get_main_queue(), ^{ done(feed, nil); });
            });
        }];
}

- (void)feedAtPath:(NSString *)path completion:(TMFeedBlock)done {
    [self feedAtURL:[self.serverURL stringByAppendingString:path] completion:done];
}

#pragma mark - Endpoints

- (void)popular:(TMFeedBlock)done {
    [self feedAtPath:@"/feeds/api/standardfeeds/most_popular?max-results=25" completion:done];
}

- (void)searchVideos:(NSString *)query completion:(TMFeedBlock)done {
    [self feedAtPath:[NSString stringWithFormat:@"/feeds/api/videos?q=%@&max-results=20", [TMAPIClient escape:query]]
          completion:done];
}

- (void)searchChannels:(NSString *)query completion:(TMFeedBlock)done {
    [self feedAtPath:[NSString stringWithFormat:@"/feeds/api/channels?q=%@&max-results=20", [TMAPIClient escape:query]]
          completion:done];
}

- (void)related:(NSString *)videoID completion:(TMFeedBlock)done {
    [self feedAtPath:[NSString stringWithFormat:@"/feeds/api/videos/%@/related?max-results=20", videoID] completion:done];
}

- (void)comments:(NSString *)videoID completion:(TMFeedBlock)done {
    [self feedAtPath:[NSString stringWithFormat:@"/feeds/api/videos/%@/comments?max-results=20", videoID]
          completion:done];
}

- (void)uploads:(NSString *)channelID completion:(TMFeedBlock)done {
    [self feedAtPath:[NSString stringWithFormat:@"/feeds/api/users/%@/uploads?max-results=25", channelID]
          completion:done];
}

- (void)video:(NSString *)videoID completion:(void (^)(TMVideo *, NSString *))done {
    [self feedAtPath:[NSString stringWithFormat:@"/feeds/api/videos/%@", videoID]
          completion:^(TMFeed *feed, NSString *error) {
              TMVideo *v = feed.entries.count ? feed.entries[0] : nil;
              done([v isKindOfClass:[TMVideo class]] ? v : nil, error ?: (v ? nil : @"Không đọc được thông tin video."));
          }];
}

- (void)streams:(NSString *)videoID fresh:(BOOL)fresh completion:(void (^)(TMStreamSet *, NSString *))done {
    NSString *path = [NSString stringWithFormat:@"/tm/v1/videos/%@/streams%@", videoID, fresh ? @"?fresh=1" : @""];
    [self getURL:[self.serverURL stringByAppendingString:path]
        completion:^(NSData *data, NSString *error) {
            if (error) {
                done(nil, error);
                return;
            }
            TMStreamSet *set = [TMExtParser parseStreams:data];
            done(set, set ? nil : @"Máy chủ không trả link phát nào cho video này.");
        }];
}

- (void)ping:(void (^)(TMPing *, NSString *))done {
    [self getURL:[self.serverURL stringByAppendingString:@"/tm/v1/ping"]
        completion:^(NSData *data, NSString *error) {
            if (error) {
                done(nil, error);
                return;
            }
            TMPing *p = [TMExtParser parsePing:data];
            done(p, p ? nil : @"Địa chỉ này không phải máy chủ TubeMini (hoặc máy chủ quá cũ).");
        }];
}

@end
