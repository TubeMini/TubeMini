#import "TMUpdater.h"
#import <CommonCrypto/CommonDigest.h>
#import <spawn.h>
#import <sys/wait.h>
#import "TMLog.h"

NSString *const TMUpdaterDidChangeNotification = @"TMUpdaterDidChange";

static NSString *const kDefaultFeed = @"https://tubemini.github.io/update.json";
static NSString *const kFeedKey = @"TMUpdateFeedURL";
static NSString *const kLastCheckKey = @"TMUpdateLastCheck";
static NSString *const kHelper = @"/usr/libexec/tubemini/tmupdate";
static const NSTimeInterval kCheckEvery = 24 * 3600;

extern char **environ;

static NSString *updateDir(void) {
    return @"/var/mobile/Documents/TubeMini-Update"; // the helper only accepts packages from here
}

@implementation TMUpdater {
    NSDictionary *_latest; // update.json
    NSURLConnection *_download;
    NSFileHandle *_file;
    long long _received, _expected;
    NSTimer *_installWatch;
    NSDate *_installStarted;
}

+ (instancetype)shared {
    static TMUpdater *u;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ u = [[TMUpdater alloc] init]; });
    return u;
}

+ (NSString *)currentVersion {
    return [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"0";
}

+ (NSInteger)compareVersion:(NSString *)a with:(NSString *)b {
    NSArray *x = [a componentsSeparatedByString:@"."], *y = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(x.count, y.count); i++) {
        NSInteger p = i < x.count ? [x[i] integerValue] : 0, q = i < y.count ? [y[i] integerValue] : 0;
        if (p != q) return p < q ? -1 : 1;
    }
    return 0;
}

- (NSString *)feedURL {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kFeedKey] ?: kDefaultFeed;
}

- (void)setFeedURL:(NSString *)feedURL {
    if (feedURL.length) {
        [[NSUserDefaults standardUserDefaults] setObject:feedURL forKey:kFeedKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kFeedKey];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)latestVersion {
    return _latest[@"version"];
}

- (NSString *)notes {
    return _latest[@"notes"];
}

- (BOOL)updateAvailable {
    return self.latestVersion.length && [TMUpdater compareVersion:self.latestVersion with:[TMUpdater currentVersion]] > 0;
}

- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:TMUpdaterDidChangeNotification object:self];
}

#pragma mark - Check

- (void)check:(void (^)(NSString *))done {
    if (_busy) {
        if (done) done(nil);
        return;
    }
    _busy = YES;
    _status = @"Đang kiểm tra…";
    [self changed];
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:self.feedURL]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:20];
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *r, NSData *data, NSError *e) {
                               self->_busy = NO;
                               self->_status = nil;
                               NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                               NSString *error = nil;
                               if (![json isKindOfClass:[NSDictionary class]] || ![json[@"version"] length] || ![json[@"url"] length]) {
                                   error = e ? @"Không kết nối được tới trang cập nhật." : @"Trang cập nhật trả dữ liệu lạ.";
                               } else {
                                   self->_latest = json;
                                   [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kLastCheckKey];
                                   [[NSUserDefaults standardUserDefaults] synchronize];
                                   TMLog(@"[update] đang dùng %@, mới nhất %@", [TMUpdater currentVersion], json[@"version"]);
                               }
                               [self changed];
                               if (done) done(error);
                           }];
}

- (void)checkQuietly {
    NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:kLastCheckKey];
    if (last && -[last timeIntervalSinceNow] < kCheckEvery) return;
    [self check:^(NSString *error) {
        if (error || !self.updateAvailable) return;
        [self offer];
    }];
}

- (void)offer {
    NSString *message = [NSString stringWithFormat:@"Đang dùng %@.%@%@", [TMUpdater currentVersion], self.notes.length ? @"\n\n" : @"",
                                                   self.notes ?: @""];
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Có TubeMini %@", self.latestVersion]
                                                message:message
                                               delegate:self
                                      cancelButtonTitle:@"Để sau"
                                      otherButtonTitles:@"Cập nhật", nil];
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != alertView.cancelButtonIndex) [self install];
}

#pragma mark - Download

- (void)install {
    if (_busy || !self.updateAvailable) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:kHelper]) {
        [self fail:@"Thiếu công cụ cài đặt. Hãy cập nhật TubeMini qua Cydia (nguồn tubemini.github.io/cydia)."];
        return;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:updateDir() withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [updateDir() stringByAppendingPathComponent:@"update.deb"];
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    _file = [NSFileHandle fileHandleForWritingAtPath:path];
    _received = 0;
    _expected = [_latest[@"size"] longLongValue];
    _busy = YES;
    _status = @"Đang tải bản cập nhật…";
    [self changed];
    TMLog(@"[update] tải %@", _latest[@"url"]);
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:_latest[@"url"]]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:30];
    _download = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}

- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)response {
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status != 200) {
        [c cancel];
        [self fail:[NSString stringWithFormat:@"Không tải được bản cập nhật (%ld).", (long)status]];
        return;
    }
    if (response.expectedContentLength > 0) _expected = response.expectedContentLength;
}

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    [_file writeData:data];
    _received += (long long)data.length;
    _status = _expected > 0 ? [NSString stringWithFormat:@"Đang tải %d%%", (int)(100 * _received / _expected)] : @"Đang tải…";
    [self changed];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    [self fail:@"Mất kết nối khi tải bản cập nhật."];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    [_file closeFile];
    _file = nil;
    _download = nil;
    NSString *path = [updateDir() stringByAppendingPathComponent:@"update.deb"];
    NSData *deb = [NSData dataWithContentsOfFile:path];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(deb.bytes, (CC_LONG)deb.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    if (![hex isEqualToString:[_latest[@"sha256"] lowercaseString]]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [self fail:@"Bản cập nhật tải về bị hỏng (sai SHA-256). Thử lại sau."];
        return;
    }
    [self runHelper:path];
}

#pragma mark - Install

- (void)runHelper:(NSString *)path {
    NSString *log = [updateDir() stringByAppendingPathComponent:@"install.log"];
    [[NSFileManager defaultManager] removeItemAtPath:log error:nil];
    _status = @"Đang cài… Màn hình chính sẽ khởi động lại.";
    [self changed];
    TMLog(@"[update] cài %@ (%lld byte)", self.latestVersion, _received);
    pid_t pid;
    const char *argv[] = {kHelper.fileSystemRepresentation, path.fileSystemRepresentation, NULL};
    int err = posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, environ);
    int status = 0;
    if (err == 0) waitpid(pid, &status, 0); // returns at once: the helper detaches to install
    if (err != 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        [self fail:[NSString stringWithFormat:@"Không chạy được công cụ cài đặt (mã %d). Cập nhật qua Cydia.",
                                              err ?: WEXITSTATUS(status)]];
        return;
    }
    // On success SpringBoard restarts and this app is closed. Still here after a while: read the log.
    _installStarted = [NSDate date];
    _installWatch = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(watchInstall) userInfo:nil repeats:YES];
}

- (void)watchInstall {
    NSString *log = [NSString stringWithContentsOfFile:[updateDir() stringByAppendingPathComponent:@"install.log"]
                                              encoding:NSUTF8StringEncoding
                                                 error:nil];
    NSRange r = [log rangeOfString:@"dpkg exit "];
    if (r.location != NSNotFound && ![[log substringFromIndex:NSMaxRange(r)] hasPrefix:@"0"]) {
        TMLog(@"[update] lỗi cài:\n%@", log);
        [self fail:@"Cài bản cập nhật bị lỗi (có thể Cydia đang mở). Đóng Cydia rồi thử lại."];
    } else if (-[_installStarted timeIntervalSinceNow] > 120) {
        [self fail:@"Cài bản cập nhật quá lâu. Thử lại, hoặc cập nhật qua Cydia."];
    }
}

- (void)fail:(NSString *)message {
    [_download cancel];
    _download = nil;
    [_file closeFile];
    _file = nil;
    [_installWatch invalidate];
    _installWatch = nil;
    _busy = NO;
    _status = nil;
    TMLog(@"[update] %@", message);
    [self changed];
    [[[UIAlertView alloc] initWithTitle:@"Không cập nhật được" message:message delegate:nil cancelButtonTitle:@"Đóng"
                      otherButtonTitles:nil] show];
}

@end
