#import <Foundation/Foundation.h>
#import "TMModels.h"

/// Reads GData Atom (a `<feed>` or a single `<entry>`) from tubemini-server into models.
/// Entry type comes from `<category scheme='…#kind' term='…#video|channel|comment|playlistLink'>`.
/// Missing tags keep model defaults; a parse error returns the entries read so far (never throws).
@interface TMAtomParser : NSObject <NSXMLParserDelegate>
+ (TMFeed *)parseFeed:(NSData *)data;
/// ISO 8601 as the server writes it (`2026-11-15T08:03:22.000Z`); nil for empty or 1970.
+ (NSDate *)dateFromString:(NSString *)s;
@end
