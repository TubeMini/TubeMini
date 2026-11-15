#import "TMImageLoader.h"
#import "TMTheme.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

static char kWantedURLKey;
static const NSTimeInterval kDiskMaxAge = 7 * 86400;

@implementation TMImageLoader {
    NSCache *_memory;
    NSOperationQueue *_network;
    dispatch_queue_t _io;
    NSString *_dir;
}

+ (instancetype)shared {
    static TMImageLoader *loader;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ loader = [[TMImageLoader alloc] init]; });
    return loader;
}

- (instancetype)init {
    if ((self = [super init])) {
        _memory = [[NSCache alloc] init];
        _memory.countLimit = 150;
        _memory.totalCostLimit = 8 * 1024 * 1024; // decoded bytes; the iPad mini has 512 MB
        _network = [[NSOperationQueue alloc] init];
        _network.maxConcurrentOperationCount = 4;
        _io = dispatch_queue_create("vn.tubemini.io.images", DISPATCH_QUEUE_CONCURRENT);
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
        _dir = [caches stringByAppendingPathComponent:@"TMImages"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_dir withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clearMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
        [self pruneDiskSoon];
    }
    return self;
}

- (void)clearMemory {
    [_memory removeAllObjects];
}

+ (UIImage *)placeholderOfSize:(CGSize)size {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    TMTheme *theme = [TMTheme current];
    NSString *key = [NSString stringWithFormat:@"%@|%d", NSStringFromCGSize(size), theme.dark];
    UIImage *img = [cache objectForKey:key];
    if (!img) {
        UIGraphicsBeginImageContextWithOptions(size, YES, 0);
        [theme.placeholder setFill];
        UIRectFill(CGRectMake(0, 0, size.width, size.height));
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [cache setObject:img forKey:key];
    }
    return img;
}

- (NSString *)pathForURL:(NSURL *)url {
    const char *s = url.absoluteString.UTF8String;
    unsigned char md5[CC_MD5_DIGEST_LENGTH];
    CC_MD5(s, (CC_LONG)strlen(s), md5);
    NSMutableString *name = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [name appendFormat:@"%02x", md5[i]];
    return [_dir stringByAppendingPathComponent:name];
}

/// Decodes into a bitmap no larger than `size` (points × screen scale), so the main thread only blits.
+ (UIImage *)decoded:(NSData *)data size:(CGSize)size {
    UIImage *raw = [UIImage imageWithData:data];
    if (!raw || raw.size.width < 1 || raw.size.height < 1) return nil;
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat ratio = MIN(1.0, MIN(size.width * scale / raw.size.width, size.height * scale / raw.size.height));
    if (size.width <= 0 || size.height <= 0) ratio = 1.0;
    CGSize target = CGSizeMake(floor(raw.size.width * ratio), floor(raw.size.height * ratio));
    UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
    [raw drawInRect:CGRectMake(0, 0, target.width, target.height)];
    CGImageRef cg = CGBitmapContextCreateImage(UIGraphicsGetCurrentContext());
    UIGraphicsEndImageContext();
    if (!cg) return raw;
    UIImage *img = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return img;
}

- (void)setImageURL:(NSURL *)url onImageView:(UIImageView *)view placeholder:(UIImage *)placeholder size:(CGSize)size {
    objc_setAssociatedObject(view, &kWantedURLKey, url.absoluteString, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSString *key = [NSString stringWithFormat:@"%@|%.0fx%.0f", url.absoluteString, size.width, size.height];
    UIImage *hit = url ? [_memory objectForKey:key] : nil;
    view.image = hit ?: placeholder;
    if (hit || !url) return;

    __weak UIImageView *weakView = view;
    void (^show)(UIImage *) = ^(UIImage *img) {
        if (!img) return;
        NSUInteger cost = (NSUInteger)(img.size.width * img.size.height * img.scale * img.scale * 4);
        [self->_memory setObject:img forKey:key cost:cost];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImageView *v = weakView;
            // The cell may have been reused for another item meanwhile
            if (v && [objc_getAssociatedObject(v, &kWantedURLKey) isEqualToString:url.absoluteString]) v.image = img;
        });
    };

    NSString *path = [self pathForURL:url];
    dispatch_async(_io, ^{
        NSData *disk = [NSData dataWithContentsOfFile:path];
        UIImage *img = disk ? [TMImageLoader decoded:disk size:size] : nil;
        if (img) {
            show(img);
            return;
        }
        NSURLRequest *req = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:20];
        [NSURLConnection sendAsynchronousRequest:req
                                           queue:self->_network
                               completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
                                   NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]]
                                                          ? ((NSHTTPURLResponse *)resp).statusCode
                                                          : 0;
                                   if (err || status != 200 || !data.length) return; // keep the placeholder
                                   dispatch_async(self->_io, ^{
                                       UIImage *fresh = [TMImageLoader decoded:data size:size];
                                       if (fresh) [data writeToFile:path atomically:YES];
                                       show(fresh);
                                   });
                               }];
    });
}

/// Drops disk entries older than a week (runs once, a few seconds after start).
- (void)pruneDiskSoon {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                       NSFileManager *fm = [NSFileManager defaultManager];
                       for (NSString *name in [fm contentsOfDirectoryAtPath:self->_dir error:NULL]) {
                           NSString *p = [self->_dir stringByAppendingPathComponent:name];
                           NSDate *mod = [fm attributesOfItemAtPath:p error:NULL].fileModificationDate;
                           if (mod && -[mod timeIntervalSinceNow] > kDiskMaxAge) [fm removeItemAtPath:p error:NULL];
                       }
                   });
}

@end
