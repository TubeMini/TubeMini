#import <Foundation/Foundation.h>

/// Vietnamese display formatting.
@interface TMFormat : NSObject
/// 293 → "4:53", 4900 → "1:21:40"; 0 → "" (unknown / live).
+ (NSString *)duration:(NSInteger)seconds;
/// 1234 → "1.234", 159000 → "159 N", 6900000 → "6,9 Tr", 1200000000 → "1,2 T".
+ (NSString *)count:(long long)n;
/// "6,9 Tr lượt xem".
+ (NSString *)views:(long long)n;
/// "3 ngày trước"; nil → "".
+ (NSString *)relativeDate:(NSDate *)date;
/// Joins non-empty parts with " · ".
+ (NSString *)join:(NSArray *)parts;
@end
