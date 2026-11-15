#import "TMLog.h"
#include <sys/sysctl.h>

NSString *TMDocumentsDir(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
}

NSString *TMLogPath(void) {
    return [TMDocumentsDir() stringByAppendingPathComponent:@"TubeMini.log"];
}

NSString *TMDeviceModel(void) {
    char buf[64] = {0};
    size_t len = sizeof(buf) - 1;
    if (sysctlbyname("hw.machine", buf, &len, NULL, 0) != 0) return @"?";
    return [NSString stringWithUTF8String:buf] ?: @"?";
}

void TMLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@", msg);

    static dispatch_queue_t queue;
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("vn.tubemini.io.log", DISPATCH_QUEUE_SERIAL);
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss.SSS";
    });
    NSDate *now = [NSDate date];
    dispatch_async(queue, ^{
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [fmt stringFromDate:now], msg];
        NSString *path = TMLogPath();
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    });
}
