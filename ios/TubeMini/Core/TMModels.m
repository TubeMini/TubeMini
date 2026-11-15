#import "TMModels.h"

@implementation TMVideo
- (instancetype)init {
    if ((self = [super init])) {
        _videoID = _title = _author = _authorID = _descriptionText = @"";
    }
    return self;
}
- (NSURL *)thumbnailURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/mqdefault.jpg", self.videoID]];
}
@end

@implementation TMChannel
- (instancetype)init {
    if ((self = [super init])) {
        _channelID = _name = _summary = _avatarURL = @"";
    }
    return self;
}
@end

@implementation TMComment
- (instancetype)init {
    if ((self = [super init])) {
        _author = _authorID = _text = @"";
    }
    return self;
}
@end

@implementation TMPlaylist
- (instancetype)init {
    if ((self = [super init])) {
        _playlistID = _title = _author = _thumbnailURL = @"";
    }
    return self;
}
@end

@implementation TMFeed
- (instancetype)init {
    if ((self = [super init])) {
        _entries = @[];
    }
    return self;
}
@end

@implementation TMStream
@end

@implementation TMStreamSet
- (instancetype)init {
    if ((self = [super init])) {
        _streams = @[];
    }
    return self;
}
- (TMStream *)streamOfKind:(NSString *)kind {
    for (TMStream *s in self.streams) {
        if ([s.kind isEqualToString:kind]) return s;
    }
    return nil;
}
- (TMStream *)streamForQuality:(NSInteger)quality {
    TMStream *hls = [self streamOfKind:@"hls"];
    TMStream *mp4 = [self streamOfKind:@"mp4"];
    if (quality >= 720 && hls) return hls;
    if (mp4) return mp4;
    return hls;
}
@end

@implementation TMPing
@end
