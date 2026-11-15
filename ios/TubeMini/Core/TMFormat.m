#import "TMFormat.h"

@implementation TMFormat

+ (NSString *)duration:(NSInteger)seconds {
    if (seconds <= 0) return @"";
    NSInteger h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60;
    if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

/// One decimal with a comma, dropping ",0": 6.94 → "6,9", 159.0 → "159".
+ (NSString *)shortNumber:(double)v {
    if (v >= 100) return [NSString stringWithFormat:@"%.0f", floor(v)];
    double rounded = floor(v * 10) / 10;
    if (rounded == floor(rounded)) return [NSString stringWithFormat:@"%.0f", rounded];
    return [[NSString stringWithFormat:@"%.1f", rounded] stringByReplacingOccurrencesOfString:@"." withString:@","];
}

+ (NSString *)count:(long long)n {
    if (n >= 1000000000LL) return [NSString stringWithFormat:@"%@ T", [self shortNumber:n / 1e9]];
    if (n >= 1000000LL) return [NSString stringWithFormat:@"%@ Tr", [self shortNumber:n / 1e6]];
    if (n >= 10000LL) return [NSString stringWithFormat:@"%@ N", [self shortNumber:n / 1e3]];
    if (n >= 1000LL) return [NSString stringWithFormat:@"%lld.%03lld", n / 1000, n % 1000];
    return [NSString stringWithFormat:@"%lld", n];
}

+ (NSString *)views:(long long)n {
    if (n <= 0) return @"";
    return [NSString stringWithFormat:@"%@ lượt xem", [self count:n]];
}

+ (NSString *)relativeDate:(NSDate *)date {
    if (!date) return @"";
    NSTimeInterval age = -[date timeIntervalSinceNow];
    if (age < 60) return @"vừa xong";
    struct {
        double seconds;
        __unsafe_unretained NSString *unit;
    } units[] = {
        {365 * 86400.0, @"năm"}, {30 * 86400.0, @"tháng"}, {7 * 86400.0, @"tuần"},
        {86400.0, @"ngày"},      {3600.0, @"giờ"},          {60.0, @"phút"},
    };
    for (size_t i = 0; i < sizeof(units) / sizeof(units[0]); i++) {
        if (age >= units[i].seconds) {
            return [NSString stringWithFormat:@"%ld %@ trước", (long)(age / units[i].seconds), units[i].unit];
        }
    }
    return @"";
}

+ (NSString *)join:(NSArray *)parts {
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *p in parts) {
        if ([p isKindOfClass:[NSString class]] && p.length) [kept addObject:p];
    }
    return [kept componentsJoinedByString:@" · "];
}

@end
