#import <Foundation/Foundation.h>
#import "TMModels.h"

/// Reads the `tm:` responses of `/tm/v1` (docs/API.md).
@interface TMExtParser : NSObject <NSXMLParserDelegate>
+ (TMStreamSet *)parseStreams:(NSData *)data;
+ (TMPing *)parsePing:(NSData *)data;
/// Attributes of the first `name` element (e.g. "tm:history"), or nil.
+ (NSDictionary *)attributesOf:(NSString *)name in:(NSData *)data;
/// `message` of a `<tm:error>`, or nil when the data is not one.
+ (NSString *)errorMessageIn:(NSData *)data;
@end
