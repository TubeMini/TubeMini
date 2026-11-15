#import <Foundation/Foundation.h>

/// A video as listed in GData feeds. Missing values: empty strings, 0, nil date.
@interface TMVideo : NSObject
@property (nonatomic, copy) NSString *videoID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *authorID;
@property (nonatomic, copy) NSString *descriptionText;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, assign) long long views;
@property (nonatomic, strong) NSDate *published;
/// 320×180 JPEG on i.ytimg.com.
- (NSURL *)thumbnailURL;
@end

@interface TMChannel : NSObject
@property (nonatomic, copy) NSString *channelID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, assign) long long subscribers;
@property (nonatomic, assign) long long videoCount;
@end

@interface TMComment : NSObject
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *authorID;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSDate *published;
@property (nonatomic, assign) NSInteger replies;
@end

@interface TMPlaylist : NSObject
@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, copy) NSString *thumbnailURL;
@end

/// One page of a GData feed: TMVideo / TMChannel / TMComment / TMPlaylist entries + next page link.
@interface TMFeed : NSObject
@property (nonatomic, strong) NSArray *entries;
@property (nonatomic, copy) NSString *nextURL;
@end

/// One `<tm:stream>` of `/tm/v1/videos/{id}/streams`.
@interface TMStream : NSObject
@property (nonatomic, assign) NSInteger quality;
@property (nonatomic, copy) NSString *kind; // "mp4" or "hls"
@property (nonatomic, copy) NSString *url;
@end

@interface TMStreamSet : NSObject
@property (nonatomic, copy) NSString *videoID;
@property (nonatomic, assign) NSInteger availableIn;
@property (nonatomic, assign) long long expire;
@property (nonatomic, strong) NSArray *streams;
/// HLS for ≥ 720 when available, otherwise the MP4 (or whatever exists).
- (TMStream *)streamForQuality:(NSInteger)quality;
- (TMStream *)streamOfKind:(NSString *)kind;
@end

/// `/tm/v1/ping`.
@interface TMPing : NSObject
@property (nonatomic, copy) NSString *server;
@property (nonatomic, copy) NSString *ytdlp;
@property (nonatomic, copy) NSString *deno;
@property (nonatomic, copy) NSString *auth;
@end
