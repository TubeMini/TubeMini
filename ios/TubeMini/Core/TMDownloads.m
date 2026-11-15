#import "TMDownloads.h"
#import <UIKit/UIKit.h>
#import "TMAPIClient.h"
#import "TMLibrary.h"
#import "TMLocalServer.h"
#import "TMLog.h"

NSString *const TMDownloadsDidChangeNotification = @"TMDownloadsDidChange";

static NSString *downloadsDir(void) {
    return [TMDocumentsDir() stringByAppendingPathComponent:@"TubeMini-Downloads"];
}

static const NSInteger kMaxLinkRetries = 3;   // fresh links / reconnects per download
static const NSInteger kMaxSegmentTries = 4;  // per HLS segment, on network errors
static const NSInteger kWorkers = 3;          // HLS segments in flight
static const long long kKeepFree = 300LL << 20; // leave this much free space on the iPad

static long long folderSize(NSString *dir) {
    long long sum = 0;
    NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtPath:dir];
    while ([e nextObject]) sum += (long long)[e.fileAttributes fileSize];
    return sum;
}

#pragma mark - Item

@implementation TMDownload

- (NSString *)folder {
    return [downloadsDir() stringByAppendingPathComponent:[self.videoID stringByAppendingString:@"-hls"]];
}

- (NSString *)filePath {
    if (self.hls) return [[self folder] stringByAppendingPathComponent:@"master.m3u8"];
    return [downloadsDir() stringByAppendingPathComponent:[self.videoID stringByAppendingPathExtension:@"mp4"]];
}

/// The MP4, or the HLS folder.
- (NSString *)storagePath {
    return self.hls ? [self folder] : [self filePath];
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

- (NSString *)qualityText {
    return [NSString stringWithFormat:@"%ldp", (long)(self.quality ?: 360)];
}

- (NSString *)statusText {
    NSString *q = [self qualityText];
    switch (self.state) {
    case TMDownloadDone:
        return [NSString stringWithFormat:@"%@ · %@", q, [TMDownloads megabytes:self.received]];
    case TMDownloadFailed:
        return [NSString stringWithFormat:@"Lỗi: %@ Chạm để thử lại.", self.error ?: @"không rõ."];
    case TMDownloadWaiting:
        return self.received > 0 ? [NSString stringWithFormat:@"Đang chờ · %@ · đã có %@", q, [TMDownloads megabytes:self.received]]
                                 : [NSString stringWithFormat:@"Đang chờ tải · %@", q];
    case TMDownloadRunning: {
        int percent = -1;
        if (self.hls && self.segmentsTotal > 0) percent = (int)(100 * self.segmentsDone / self.segmentsTotal);
        else if (!self.hls && self.total > 0) percent = (int)(100 * self.received / self.total);
        NSString *size = self.total > 0 ? [NSString stringWithFormat:@"%@ / %@%@", [TMDownloads megabytes:self.received],
                                                                     self.hls ? @"~" : @"", [TMDownloads megabytes:self.total]]
                                        : [TMDownloads megabytes:self.received];
        return percent >= 0 ? [NSString stringWithFormat:@"Đang tải %d%% · %@ · %@", percent, q, size]
                            : [NSString stringWithFormat:@"Đang tải · %@ · %@", q, size];
    }
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
        @"quality" : @(self.quality),
        @"hls" : @(self.hls),
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
    x.quality = [d[@"quality"] integerValue] ?: 360;
    x.hls = [d[@"hls"] boolValue];
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
    NSInteger _linkRetries;
    NSDate *_lastNotify;
    UIBackgroundTaskIdentifier _bgTask;
    // MP4
    NSURLConnection *_connection;
    NSFileHandle *_file;
    NSString *_url;
    // HLS
    NSInteger _gen;              // bumps on stop: late callbacks of an old run are ignored
    NSArray *_segURLs, *_segPaths;
    NSMutableIndexSet *_segDone, *_inFlight;
    NSMutableDictionary *_tries; // segment index → failed attempts
    NSInteger _active;
    BOOL _refreshing;
    NSOperationQueue *_net;
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
        _net = [[NSOperationQueue alloc] init];
        _net.maxConcurrentOperationCount = kWorkers;
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:downloadsDir() withIntermediateDirectories:YES attributes:nil error:nil];
        // Big files the user can download again: keep them out of iCloud / iTunes backups
        [[NSURL fileURLWithPath:downloadsDir()] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        [TMLocalServer shared].root = downloadsDir();
        _items = [NSMutableArray array];
        for (NSDictionary *d in [NSArray arrayWithContentsOfFile:[self indexPath]] ?: @[]) {
            TMDownload *x = [TMDownload fromPlist:d];
            if (!x) continue;
            // Trust the disk over the index (the app may have been killed mid-write)
            x.received = x.hls ? folderSize([x storagePath]) : (long long)[[fm attributesOfItemAtPath:x.filePath error:nil] fileSize];
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

/// Progress ticks: at most twice a second.
- (void)progressed:(TMDownload *)x {
    if (_lastNotify && -[_lastNotify timeIntervalSinceNow] < 0.5) return;
    _lastNotify = [NSDate date];
    [self changed:x];
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
    [self add:video quality:360 hls:NO estimate:0];
}

- (void)add:(TMVideo *)video quality:(NSInteger)quality hls:(BOOL)hls estimate:(long long)estimate {
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
    x.quality = quality;
    x.hls = hls;
    x.total = estimate;
    x.added = [NSDate date];
    x.state = TMDownloadWaiting;
    long long free = [[[NSFileManager defaultManager] attributesOfFileSystemForPath:downloadsDir() error:nil][NSFileSystemFreeSize]
                         longLongValue];
    if (estimate > 0 && free > 0 && estimate > free - kKeepFree) {
        x.state = TMDownloadFailed;
        x.error = [NSString stringWithFormat:@"iPad không đủ chỗ (cần khoảng %@, còn %@).", [TMDownloads megabytes:estimate],
                                             [TMDownloads megabytes:MAX(free - kKeepFree, 0)]];
    }
    [_items insertObject:x atIndex:0];
    TMLog(@"[download] thêm %@ %ldp%@ (%@)", x.videoID, (long)quality, hls ? @" HLS" : @"", x.title);
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
    [[NSFileManager defaultManager] removeItemAtPath:[x storagePath] error:nil];
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

- (void)start:(TMDownload *)x {
    _current = x;
    _linkRetries = 0;
    x.state = TMDownloadRunning;
    [self changed:x];
    [self beginBackgroundTask];
    if (x.hls) {
        [self fetchPlaylists:NO];
    } else {
        [self fetchLink:NO];
    }
}

- (void)finish {
    TMDownload *x = _current;
    x.state = TMDownloadDone;
    if (x.hls) x.received = folderSize([x storagePath]);
    x.total = x.received;
    TMLog(@"[download] xong %@ %ldp: %@", x.videoID, (long)x.quality, [TMDownloads megabytes:x.received]);
    _current = nil;
    [self save];
    [self changed:x];
    [self resume];
}

- (void)fail:(NSString *)message {
    TMDownload *x = _current;
    [self stopTransfers];
    x.state = TMDownloadFailed;
    x.error = message;
    TMLog(@"[download] lỗi %@: %@", x.videoID, message);
    _current = nil;
    [self save];
    [self changed:x];
    [self resume];
}

/// Stops the running transfer (the item goes back to waiting; what is on disk stays).
- (void)stopCurrent {
    [self stopTransfers];
    if (_current.state == TMDownloadRunning) _current.state = TMDownloadWaiting;
    _current = nil;
    [self save];
}

- (void)stopTransfers {
    [_connection cancel];
    _connection = nil;
    [_file closeFile];
    _file = nil;
    _gen++;
    _active = 0;
    _refreshing = NO;
    [_inFlight removeAllIndexes];
}

#pragma mark - MP4

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
                               [self after:set.availableIn run:^{
                                   if (x == self->_current) [self connect];
                               }];
                           }
                       }];
}

- (void)after:(NSInteger)seconds run:(dispatch_block_t)block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(seconds, 0) * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)connect {
    TMDownload *x = _current;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:x.filePath]) [fm createFileAtPath:x.filePath contents:nil attributes:nil];
    x.received = (long long)[[fm attributesOfItemAtPath:x.filePath error:nil] fileSize];
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
        [self mp4Finished];
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
    _current.received += (long long)data.length;
    [self progressed:_current];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    [self mp4Finished];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    TMLog(@"[download] %@ đứt: %@", _current.videoID, error.localizedDescription);
    [_file closeFile];
    _file = nil;
    _connection = nil;
    // Dropped mid-way: try again from where it stopped, a few times
    if (++_linkRetries <= kMaxLinkRetries) {
        TMDownload *x = _current;
        [self after:3 run:^{
            if (x == self->_current && !self->_connection) [self connect];
        }];
    } else {
        [self fail:@"Mất kết nối khi đang tải."];
    }
}

- (void)mp4Finished {
    TMDownload *x = _current;
    [_file closeFile];
    _file = nil;
    _connection = nil;
    if (x.total > 0 && x.received < x.total) {
        [self connection:nil didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil]];
        return;
    }
    [self finish];
}

#pragma mark - HLS

/// The HLS entry of `streams` for the wanted level (highest not above it).
- (TMStream *)hlsStreamIn:(TMStreamSet *)set quality:(NSInteger)quality {
    TMStream *best = nil;
    for (TMStream *s in set.streams) {
        if (![s.kind isEqualToString:@"hls"] || s.quality > quality) continue;
        if (!best || s.quality > best.quality) best = s;
    }
    return best;
}

/// Plain GET (googlevideo / proxy URLs: no server token) on the main queue.
- (void)get:(NSString *)url done:(void (^)(NSString *text, NSInteger status))done {
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:url]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:30];
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *r, NSData *data, NSError *e) {
                               NSInteger status = [r isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r statusCode] : 0;
                               NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
                               done(status == 200 ? text : nil, status);
                           }];
}

/// streams → the server's master playlist for the level → the video / audio media playlists.
/// Writes the local playlists and (re)builds the segment URL list, then downloads what is missing.
- (void)fetchPlaylists:(BOOL)fresh {
    TMDownload *x = _current;
    NSInteger gen = _gen;
    _refreshing = YES;
    [[TMAPIClient shared] streams:x.videoID
                            fresh:fresh
                       completion:^(TMStreamSet *set, NSString *error) {
                           if (x != self->_current || gen != self->_gen) return;
                           if (error) {
                               [self fail:error];
                               return;
                           }
                           TMStream *s = [self hlsStreamIn:set quality:x.quality];
                           if (!s) {
                               [self fail:[NSString stringWithFormat:@"Video này không có bản %ldp để tải.", (long)x.quality]];
                               return;
                           }
                           x.quality = s.quality;
                           [self after:set.availableIn run:^{
                               if (x != self->_current || gen != self->_gen) return;
                               // Our server: TMAPIClient adds the token
                               [[TMAPIClient shared] getURL:s.url
                                                 completion:^(NSData *data, NSString *err) {
                                                     if (x != self->_current || gen != self->_gen) return;
                                                     NSString *master = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
                                                     if (!master.length) {
                                                         [self fail:err ?: @"Máy chủ không trả playlist."];
                                                         return;
                                                     }
                                                     [self loadMediaPlaylists:master base:s.url gen:gen];
                                                 }];
                           }];
                       }];
}

static NSString *attributeValue(NSString *line, NSString *name) {
    NSRange r = [line rangeOfString:[name stringByAppendingString:@"=\""]];
    if (r.location == NSNotFound) return nil;
    NSUInteger start = NSMaxRange(r);
    NSRange end = [line rangeOfString:@"\"" options:0 range:NSMakeRange(start, line.length - start)];
    return end.location == NSNotFound ? nil : [line substringWithRange:NSMakeRange(start, end.location - start)];
}

static NSString *absolute(NSString *uri, NSString *base) {
    return [[NSURL URLWithString:uri relativeToURL:[NSURL URLWithString:base]] absoluteString] ?: uri;
}

/// Copies a media playlist with its segment URIs replaced by `<prefix>/<n>.ts` (n from 0 in each
/// playlist); appends the segment URLs to `urls`.
static NSString *localMediaPlaylist(NSString *text, NSString *base, NSString *prefix, NSMutableArray *urls) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger first = urls.count;
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!line.length) continue;
        if ([line hasPrefix:@"#"]) {
            [out appendFormat:@"%@\n", line];
        } else {
            [out appendFormat:@"%@/%05lu.ts\n", prefix, (unsigned long)(urls.count - first)];
            [urls addObject:absolute(line, base)];
        }
    }
    return out;
}

- (void)loadMediaPlaylists:(NSString *)master base:(NSString *)masterURL gen:(NSInteger)gen {
    TMDownload *x = _current;
    NSString *audioURI = nil, *videoURI = nil;
    BOOL nextIsVariant = NO;
    NSMutableString *localMaster = [NSMutableString string];
    for (NSString *raw in [master componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!line.length) continue;
        if ([line hasPrefix:@"#EXT-X-MEDIA:"] && attributeValue(line, @"URI")) {
            NSString *uri = attributeValue(line, @"URI");
            if (!audioURI) audioURI = absolute(uri, masterURL);
            line = [line stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"URI=\"%@\"", uri] withString:@"URI=\"audio.m3u8\""];
        } else if (nextIsVariant && ![line hasPrefix:@"#"]) {
            if (!videoURI) videoURI = absolute(line, masterURL);
            line = @"video.m3u8";
            nextIsVariant = NO;
        }
        if ([line hasPrefix:@"#EXT-X-STREAM-INF:"]) nextIsVariant = YES;
        [localMaster appendFormat:@"%@\n", line];
    }
    if (!videoURI) {
        [self fail:@"Playlist không có biến thể nào."];
        return;
    }
    [self get:videoURI
         done:^(NSString *video, NSInteger vStatus) {
             if (x != self->_current || gen != self->_gen) return;
             if (!video) {
                 [self playlistFailed:vStatus];
                 return;
             }
             void (^build)(NSString *) = ^(NSString *audio) {
                 NSMutableArray *urls = [NSMutableArray array];
                 NSString *localVideo = localMediaPlaylist(video, videoURI, @"v", urls);
                 NSUInteger videoCount = urls.count;
                 NSString *localAudio = audio ? localMediaPlaylist(audio, audioURI, @"a", urls) : nil;
                 // Paths: v/00000.ts … then a/00000.ts …
                 NSString *folder = [[x filePath] stringByDeletingLastPathComponent];
                 NSFileManager *fm = [NSFileManager defaultManager];
                 [fm createDirectoryAtPath:[folder stringByAppendingPathComponent:@"v"] withIntermediateDirectories:YES attributes:nil error:nil];
                 [fm createDirectoryAtPath:[folder stringByAppendingPathComponent:@"a"] withIntermediateDirectories:YES attributes:nil error:nil];
                 NSMutableArray *paths = [NSMutableArray array];
                 for (NSUInteger i = 0; i < urls.count; i++) {
                     NSString *rel = i < videoCount ? [NSString stringWithFormat:@"v/%05lu.ts", (unsigned long)i]
                                                    : [NSString stringWithFormat:@"a/%05lu.ts", (unsigned long)(i - videoCount)];
                     [paths addObject:[folder stringByAppendingPathComponent:rel]];
                 }
                 [localVideo writeToFile:[folder stringByAppendingPathComponent:@"video.m3u8"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                 if (localAudio) {
                     [localAudio writeToFile:[folder stringByAppendingPathComponent:@"audio.m3u8"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                 }
                 [localMaster writeToFile:[x filePath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                 [self startSegments:urls paths:paths];
             };
             if (!audioURI) {
                 build(nil);
                 return;
             }
             [self get:audioURI
                  done:^(NSString *audio, NSInteger aStatus) {
                      if (x != self->_current || gen != self->_gen) return;
                      if (!audio) {
                          [self playlistFailed:aStatus];
                          return;
                      }
                      build(audio);
                  }];
         }];
}

- (void)playlistFailed:(NSInteger)status {
    if (++_linkRetries > kMaxLinkRetries) {
        [self fail:[NSString stringWithFormat:@"Không tải được playlist (%ld).", (long)status]];
    } else {
        [self fetchPlaylists:YES];
    }
}

- (void)startSegments:(NSArray *)urls paths:(NSArray *)paths {
    TMDownload *x = _current;
    BOOL first = _segPaths == nil || ![_segPaths isEqualToArray:paths];
    _segURLs = urls;
    _segPaths = paths;
    if (first || !_segDone) {
        _segDone = [NSMutableIndexSet indexSet];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSUInteger i = 0; i < paths.count; i++) {
            if ([fm fileExistsAtPath:paths[i]]) [_segDone addIndex:i];
        }
        _inFlight = [NSMutableIndexSet indexSet];
        _tries = [NSMutableDictionary dictionary];
    }
    x.segmentsTotal = (NSInteger)paths.count;
    x.segmentsDone = (NSInteger)_segDone.count;
    x.received = folderSize([[x filePath] stringByDeletingLastPathComponent]);
    TMLog(@"[download] %@ %ldp: %lu segment, đã có %lu", x.videoID, (long)x.quality, (unsigned long)paths.count,
          (unsigned long)_segDone.count);
    _refreshing = NO;
    [self changed:x];
    [self pump];
}

- (NSInteger)nextMissing {
    for (NSUInteger i = 0; i < _segPaths.count; i++) {
        if (![_segDone containsIndex:i] && ![_inFlight containsIndex:i]) return (NSInteger)i;
    }
    return -1;
}

- (void)pump {
    if (!_current || _refreshing) return;
    while (_active < kWorkers) {
        NSInteger i = [self nextMissing];
        if (i < 0) break;
        [self downloadSegment:(NSUInteger)i];
    }
    if (_active == 0 && _segDone.count == _segPaths.count) [self finish];
}

- (void)downloadSegment:(NSUInteger)i {
    NSInteger gen = _gen;
    NSString *path = _segPaths[i];
    [_inFlight addIndex:i];
    _active++;
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:_segURLs[i]]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:30];
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:_net
                           completionHandler:^(NSURLResponse *r, NSData *data, NSError *e) {
                               NSInteger status = [r isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r statusCode] : 0;
                               BOOL ok = !e && status == 200 && data.length > 0;
                               if (ok) {
                                   // Whole file or nothing: a half segment never looks done after a crash
                                   NSString *part = [path stringByAppendingString:@".part"];
                                   ok = [data writeToFile:part atomically:NO] &&
                                        [[NSFileManager defaultManager] moveItemAtPath:part toPath:path error:nil];
                               }
                               long long bytes = (long long)data.length;
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   [self segment:i ok:ok status:status bytes:bytes gen:gen];
                               });
                           }];
}

- (void)segment:(NSUInteger)i ok:(BOOL)ok status:(NSInteger)status bytes:(long long)bytes gen:(NSInteger)gen {
    if (gen != _gen || !_current) return;
    _active--;
    [_inFlight removeIndex:i];
    TMDownload *x = _current;
    if (ok) {
        [_segDone addIndex:i];
        x.segmentsDone = (NSInteger)_segDone.count;
        x.received += bytes;
        [self progressed:x];
        [self pump];
        return;
    }
    if (status == 403 || status == 410 || status == 404) {
        // Links expired: new playlists (same segments, same order), then carry on
        if (_refreshing) return;
        if (++_linkRetries > kMaxLinkRetries) {
            [self fail:[NSString stringWithFormat:@"YouTube từ chối link (%ld).", (long)status]];
            return;
        }
        TMLog(@"[download] %@: link hết hạn, xin link mới", x.videoID);
        [self fetchPlaylists:YES];
        return;
    }
    NSInteger tries = [_tries[@(i)] integerValue] + 1;
    _tries[@(i)] = @(tries);
    if (tries >= kMaxSegmentTries) {
        [self fail:@"Mất kết nối khi đang tải."];
        return;
    }
    [self after:2 run:^{
        if (gen == self->_gen) [self pump];
    }];
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
