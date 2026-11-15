#import <Foundation/Foundation.h>

/// A tiny HTTP server on 127.0.0.1 for downloaded HLS videos: iOS 6 cannot play an HLS playlist from a
/// file:// URL, but plays it fine over HTTP. GET / HEAD only, files under `root` only, Range supported,
/// one blocking thread per connection (the player opens a few at a time). Started on first use.
@interface TMLocalServer : NSObject
+ (instancetype)shared;
/// The directory served (the downloads folder).
@property (nonatomic, copy) NSString *root;
/// http://127.0.0.1:<port>/<path relative to root>, or nil when the server cannot start / the path is outside root.
- (NSURL *)urlForFile:(NSString *)path;
@end
