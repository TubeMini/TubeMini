#import "TMDownloads.h"
#import <UIKit/UIKit.h>
#import "TMAPIClient.h"
#import "TMLibrary.h"
#import "TMLog.h"

NSString *const TMDownloadsDidChangeNotification = @"TMDownloadsDidChange";

static NSString *downloadsDir(void) {
    return [TMDocumentsDir() stringByAppendingPathComponent:@"TubeMini-Downloads"];
}

static const NSInteger kMaxLinkRetries = 3;

#pragma mark - Item

@implementation TMDownload

- (NSString *)filePath {
    return [downloadsDir() stringByAppendingPathComponent:[self.videoID stringByAppendingPathExtension:@"mp4"]];
}

- (TMVideo *)video {
    TMVideo *v = [[TMVideo alloc] init];
    v.videoID = self.videoID;
    v.title = self.title;
    v.author = self.author;
    v.authorID = self.authorID;
    v.duration = self.duration;
    v.position = self.position;
    return v;
}

- (NSString *)statusText {
    switch (self.state) {
    case TMDownloadDone:
        return [TMDownloads megabytes:self.received];
    case TMDownloadFailed:
        return [NSString stringWithFormat:@"Lỗi: %@ Chạm để thử lại.", self.error ?: @"không rõ."];
    case TMDownloadWaiting:
        return self.received > 0 ? [NSString stringWithFormat:@"Đang chờ · đã có %@", [TMDownloads megabytes:self.received]]
                                 : @"Đang chờ tải";
    case TMDownloadRunning:
        if (self.total > 0) {
            return [NSString stringWithFormat:@"Đang tải %d%% · %@ / %@", (int)(100 * self.received / self.total),
                                              [TMDownloads megabytes:self.received], [TMDownloads megabytes:self.total]];
        }
        return [NSString stringWithFormat:@"Đang tải · %@", [TMDownloads megabytes:self.received]];
    }
    return @"";
}

- (NSDictionary *)plist {
    return @{
        @"id" : self.videoID ?: @"",
        @"title" : self.title ?: @"",
        @"author" : self.author ?: @"",
        @"authorID" : self.authorID ?: @"",
        @"duration" : @(self.duration),
        @"state" : @(self.state == TMDownloadRunning ? TMDownloadWaiting : self.state),
        @"received" : @(self.received),
        @"total" : @(self.total),
        @"error" : self.error ?: @"",
        @"dubbed" : @(self.dubbed),
        @"position" : @(self.position),
        @"added" : self.added ?: [NSDate date],
    };
}

+ (instancetype)fromPlist:(NSDictionary *)d {
    TMDownload *x = [[TMDownload alloc] init];
    x.videoID = d[@"id"];
    x.title = d[@"title"];
    x.author = d[@"author"];
    x.authorID = d[@"authorID"];
    x.duration = [d[@"duration"] integerValue];
    x.state = [d[@"state"] integerValue];
    x.received = [d[@"received"] longLongValue];
    x.total = [d[@"total"] longLongValue];
    x.error = [d[@"error"] length] ? d[@"error"] : nil;
    x.dubbed = [d[@"dubbed"] boolValue];
    x.position = [d[@"position"] integerValue];
    x.added = d[@"added"];
    return x.videoID.length ? x : nil;
}

@end

#pragma mark - Manager

@implementation TMDownloads {
    NSMutableArray *_items;
    TMDownload *_current;
    NSURLConnection *_connection;
    NSFileHandle *_file;
    NSString *_url;
    NSInteger _linkRetries;
    NSDate *_lastNotify;
    UIBackgroundTaskIdentifier _bgTask;
}

+ (instancetype)shared {
    static TMDownloads *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[TMDownloads alloc] init]; });
    return d;
}

+ (NSString *)megabytes:(long long)bytes {
    return [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
}

- (instancetype)init {
    if ((self = [super init])) {
        _bgTask = UIBackgroundTaskInvalid;
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:downloadsDir() withIntermediateDirectories:YES attributes:nil error:nil];
        // Big files the user can download again: keep them out of iCloud / iTunes backups
        [[NSURL fileURLWithPath:downloadsDir()] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        _items = [NSMutableArray array];
        for (NSDictionary *d in [NSArray arrayWithContentsOfFile:[self indexPath]] ?: @[]) {
            TMDownload *x = [TMDownload fromPlist:d];
            if (!x) continue;
            // Trust the file on disk over the index (the app may have been killed mid-write)
            x.received = [[fm attributesOfItemAtPath:x.filePath error:nil] fileSize];
            [_items addObject:x];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(historyChanged:)
                                                     name:TMHistoryDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(resume)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
    }
    return self;
}

- (NSString *)indexPath {
    return [downloadsDir() stringByAppendingPathComponent:@"index.plist"];
}

- (void)save {
    NSMutableArray *list = [NSMutableArray array];
    for (TMDownload *x in _items) [list addObject:[x plist]];
    [list writeToFile:[self indexPath] atomically:YES];
}

- (void)changed:(TMDownload *)x {
    NSDictionary *info = x ? @{ @"videoID" : x.videoID } : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:TMDownloadsDidChangeNotification object:self userInfo:info];
}

- (NSArray *)items {
    return [_items copy];
}

- (TMDownload *)itemFor:(NSString *)videoID {
    for (TMDownload *x in _items) {
        if ([x.videoID isEqualToString:videoID]) return x;
    }
    return nil;
}

- (long long)bytesUsed {
    long long sum = 0;
    for (TMDownload *x in _items) sum += x.received;
    return sum;
}

/// The player saved a position: remember it for offline playback of the saved copy.
- (void)historyChanged:(NSNotification *)n {
    TMDownload *x = [self itemFor:n.userInfo[@"videoID"]];
    if (!x) return;
    x.position = [n.userInfo[@"position"] integerValue];
    [self save];
}

#pragma mark - Queue

- (void)add:(TMVideo *)video {
    TMDownload *x = [self itemFor:video.videoID];
    if (x) {
        if (x.state == TMDownloadFailed) [self retry:x.videoID];
        return;
    }
    x = [[TMDownload alloc] init];
    x.videoID = video.videoID;
    x.title = video.title;
    x.author = video.author;
    x.authorID = video.authorID;
    x.duration = video.duration;
    x.position = video.position; // where the user is in it now (offline resume)
    x.added = [NSDate date];
    x.state = TMDownloadWaiting;
    [_items insertObject:x atIndex:0];
    TMLog(@"[download] thêm %@ (%@)", x.videoID, x.title);
    [self save];
    [self changed:x];
    [self resume];
}

- (void)retry:(NSString *)videoID {
    TMDownload *x = [self itemFor:videoID];
    if (!x || x.state == TMDownloadDone || x.state == TMDownloadRunning) return;
    x.state = TMDownloadWaiting;
    x.error = nil;
    [self save];
    [self changed:x];
    [self resume];
}

- (void)remove:(NSString *)videoID {
    TMDownload *x = [self itemFor:videoID];
    if (!x) return;
    if (x == _current) [self stopCurrent];
    [[NSFileManager defaultManager] removeItemAtPath:x.filePath error:nil];
    [_items removeObject:x];
    TMLog(@"[download] xoá %@", videoID);
    [self save];
    [self changed:nil];
    [self resume];
}

- (void)resume {
    if (_current) return;
    for (TMDownload *x in [_items reverseObjectEnumerator]) { // oldest first
        if (x.state == TMDownloadWaiting) {
            [self start:x];
            return;
        }
    }
    [self endBackgroundTask];
}

#pragma mark - Transfer

- (void)start:(TMDownload *)x {
    _current = x;
    _linkRetries = 0;
    x.state = TMDownloadRunning;
    [self changed:x];
    [self beginBackgroundTask];
    [self fetchLink:NO];
}

/// Asks the server for the MP4 link (fresh after a refusal), then connects.
- (void)fetchLink:(BOOL)fresh {
    TMDownload *x = _current;
    [[TMAPIClient shared] streams:x.videoID
                            fresh:fresh
                       completion:^(TMStreamSet *set, NSString *error) {
                           if (x != self->_current) return;
                           if (error) {
                               [self fail:error];
                           } else if (!set.downloadURL.length) {
                               [self fail:@"Video này không có bản MP4 để tải (chỉ phát trực tuyến được)."];
                           } else {
                               x.dubbed = set.downloadDubbed;
                               self->_url = set.downloadURL;
                               // Pre-roll ad window: the link answers 403 until then
                               dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(set.availableIn, 0) * NSEC_PER_SEC)),
                                              dispatch_get_main_queue(), ^{
                                                  if (x == self->_current) [self connect];
                                              });
                           }
                       }];
}

- (void)connect {
    TMDownload *x = _current;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:x.filePath]) [fm createFileAtPath:x.filePath contents:nil attributes:nil];
    x.received = [[fm attributesOfItemAtPath:x.filePath error:nil] fileSize];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_url]
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:30];
    if (x.received > 0) [req setValue:[NSString stringWithFormat:@"bytes=%lld-", x.received] forHTTPHeaderField:@"Range"];
    TMLog(@"[download] %@ từ byte %lld", x.videoID, x.received);
    _connection = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}

- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)response {
    TMDownload *x = _current;
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status == 403 || status == 410 || status == 404) {
        [c cancel];
        _connection = nil;
        if (++_linkRetries > kMaxLinkRetries) {
            [self fail:[NSString stringWithFormat:@"YouTube từ chối link (%ld).", (long)status]];
        } else {
            [self fetchLink:YES];
        }
        return;
    }
    if (status == 416 && x.total > 0 && x.received >= x.total) { // already complete
        [c cancel];
        [self finish];
        return;
    }
    if (status != 200 && status != 206) {
        [c cancel];
        [self fail:[NSString stringWithFormat:@"Lỗi tải (%ld).", (long)status]];
        return;
    }
    _file = [NSFileHandle fileHandleForWritingAtPath:x.filePath];
    if (status == 200) {
        // Range ignored: start over
        [_file truncateFileAtOffset:0];
        x.received = 0;
        x.total = response.expectedContentLength > 0 ? response.expectedContentLength : 0;
    } else {
        [_file seekToEndOfFile];
        NSString *range = [(NSHTTPURLResponse *)response allHeaderFields][@"Content-Range"];
        NSRange slash = [range rangeOfString:@"/"];
        long long total = slash.location != NSNotFound ? [[range substringFromIndex:slash.location + 1] longLongValue] : 0;
        x.total = total > 0 ? total : x.received + MAX(response.expectedContentLength, 0);
    }
}

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    [_file writeData:data];
    _current.received += data.length;
    if (!_lastNotify || -[_lastNotify timeIntervalSinceNow] > 0.5) {
        _lastNotify = [NSDate date];
        [self changed:_current];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    [self finish];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    TMLog(@"[download] %@ đứt: %@", _current.videoID, error.localizedDescription);
    [_file closeFile];
    _file = nil;
    _connection = nil;
    // Dropped mid-way: try again from where it stopped, a few times
    if (++_linkRetries <= kMaxLinkRetries) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self->_current && !self->_connection) [self connect];
        });
    } else {
        [self fail:@"Mất kết nối khi đang tải."];
    }
}

- (void)finish {
    TMDownload *x = _current;
    [_file closeFile];
    _file = nil;
    _connection = nil;
    if (x.total > 0 && x.received < x.total) {
        [self connection:nil didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil]];
        return;
    }
    x.state = TMDownloadDone;
    x.total = x.received;
    TMLog(@"[download] xong %@: %@", x.videoID, [TMDownloads megabytes:x.received]);
    _current = nil;
    [self save];
    [self changed:x];
    [self resume];
}

- (void)fail:(NSString *)message {
    TMDownload *x = _current;
    [_file closeFile];
    _file = nil;
    [_connection cancel];
    _connection = nil;
    x.state = TMDownloadFailed;
    x.error = message;
    TMLog(@"[download] lỗi %@: %@", x.videoID, message);
    _current = nil;
    [self save];
    [self changed:x];
    [self resume];
}

/// Stops the running transfer (the item goes back to waiting; the partial file stays).
- (void)stopCurrent {
    [_connection cancel];
    _connection = nil;
    [_file closeFile];
    _file = nil;
    if (_current.state == TMDownloadRunning) _current.state = TMDownloadWaiting;
    _current = nil;
    [self save];
}

#pragma mark - Background

- (void)beginBackgroundTask {
    if (_bgTask != UIBackgroundTaskInvalid) return;
    _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        // Out of background time: pause; the download resumes when the app is opened again
        TMLog(@"[download] hết thời gian chạy nền, tạm dừng");
        [self stopCurrent];
        [self endBackgroundTask];
    }];
}

- (void)endBackgroundTask {
    if (_bgTask == UIBackgroundTaskInvalid) return;
    [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
    _bgTask = UIBackgroundTaskInvalid;
}

@end
