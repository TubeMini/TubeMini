#import "TMLocalServer.h"
#import "TMLog.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

@implementation TMLocalServer {
    int _listenFD;
    uint16_t _port;
    dispatch_source_t _acceptSource;
}

+ (instancetype)shared {
    static TMLocalServer *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[TMLocalServer alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) _listenFD = -1;
    return self;
}

- (BOOL)start {
    if (_listenFD >= 0) return YES;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    struct sockaddr_in addr = {0};
    addr.sin_len = sizeof addr;
    addr.sin_family = AF_INET;
    addr.sin_port = 0; // any free port
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t len = sizeof addr;
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(fd, 16) != 0 ||
        getsockname(fd, (struct sockaddr *)&addr, &len) != 0) {
        close(fd);
        return NO;
    }
    _listenFD = fd;
    _port = ntohs(addr.sin_port);
    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0,
                                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    NSString *root = [self.root copy];
    dispatch_source_set_event_handler(_acceptSource, ^{
        int client = accept(fd, NULL, NULL);
        if (client < 0) return;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ serve(client, root); });
    });
    dispatch_resume(_acceptSource);
    TMLog(@"[localserver] http://127.0.0.1:%d", _port);
    return YES;
}

- (NSURL *)urlForFile:(NSString *)path {
    NSString *root = [self.root stringByStandardizingPath];
    NSString *full = [path stringByStandardizingPath];
    if (!root.length || ![full hasPrefix:[root stringByAppendingString:@"/"]] || ![self start]) return nil;
    NSString *rel = [full substringFromIndex:root.length + 1];
    NSString *escaped = [rel stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/%@", _port, escaped]];
}

#pragma mark - One connection (blocking, on a background queue)

static BOOL writeAll(int fd, const void *buf, size_t len) {
    const char *p = buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n <= 0) return NO;
        p += n;
        len -= (size_t)n;
    }
    return YES;
}

static void respond(int fd, NSString *status, NSString *headers) {
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %@\r\n%@Connection: close\r\n\r\n", status, headers ?: @""];
    NSData *d = [head dataUsingEncoding:NSUTF8StringEncoding];
    writeAll(fd, d.bytes, d.length);
}

static NSString *contentType(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"m3u8"]) return @"application/vnd.apple.mpegurl";
    if ([ext isEqualToString:@"mp4"]) return @"video/mp4";
    return @"application/octet-stream"; // what googlevideo sends for HLS segments
}

static void serve(int fd, NSString *root) {
    @autoreleasepool {
        int yes = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
        char buf[8192];
        size_t used = 0;
        while (used < sizeof buf - 1) {
            ssize_t n = read(fd, buf + used, sizeof buf - 1 - used);
            if (n <= 0) break;
            used += (size_t)n;
            buf[used] = 0;
            if (strstr(buf, "\r\n\r\n")) break;
        }
        buf[used] = 0;
        NSString *request = [[NSString alloc] initWithBytes:buf length:used encoding:NSUTF8StringEncoding];
        NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
        NSArray *first = lines.count ? [lines[0] componentsSeparatedByString:@" "] : @[];
        if (first.count < 2 || !([first[0] isEqualToString:@"GET"] || [first[0] isEqualToString:@"HEAD"])) {
            respond(fd, @"400 Bad Request", nil);
            close(fd);
            return;
        }
        BOOL head = [first[0] isEqualToString:@"HEAD"];
        NSString *rel = [[first[1] componentsSeparatedByString:@"?"][0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *path = [[root stringByAppendingPathComponent:rel] stringByStandardizingPath];
        struct stat st;
        if (![path hasPrefix:[[root stringByStandardizingPath] stringByAppendingString:@"/"]] || stat(path.fileSystemRepresentation, &st) != 0 ||
            !S_ISREG(st.st_mode)) {
            respond(fd, @"404 Not Found", @"Content-Length: 0\r\n");
            close(fd);
            return;
        }
        long long size = st.st_size, from = 0, to = size - 1;
        BOOL partial = NO;
        for (NSString *line in lines) {
            if (![line.lowercaseString hasPrefix:@"range: bytes="]) continue;
            NSArray *r = [[line substringFromIndex:13] componentsSeparatedByString:@"-"];
            if (r.count == 2) {
                if ([r[0] length]) from = [r[0] longLongValue];
                if ([r[1] length]) to = MIN([r[1] longLongValue], size - 1);
                else if (![r[0] length]) from = 0;
                partial = from <= to && from < size;
            }
        }
        if (!partial) {
            from = 0;
            to = size - 1;
        }
        NSString *headers = [NSString stringWithFormat:@"Content-Type: %@\r\nContent-Length: %lld\r\nAccept-Ranges: bytes\r\n%@",
                                                       contentType(path), size > 0 ? to - from + 1 : 0,
                                                       partial ? [NSString stringWithFormat:@"Content-Range: bytes %lld-%lld/%lld\r\n", from, to, size] : @""];
        respond(fd, partial ? @"206 Partial Content" : @"200 OK", headers);
        if (!head && size > 0) {
            int file = open(path.fileSystemRepresentation, O_RDONLY);
            if (file >= 0) {
                lseek(file, from, SEEK_SET);
                long long left = to - from + 1;
                char chunk[65536];
                while (left > 0) {
                    ssize_t n = read(file, chunk, (size_t)MIN(left, (long long)sizeof chunk));
                    if (n <= 0 || !writeAll(fd, chunk, (size_t)n)) break;
                    left -= n;
                }
                close(file);
            }
        }
        close(fd);
    }
}

@end
