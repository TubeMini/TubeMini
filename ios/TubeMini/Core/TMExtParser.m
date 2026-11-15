#import "TMExtParser.h"

@implementation TMExtParser {
    NSMutableArray *_elements; // @[name, attributes] in document order
}

+ (NSArray *)elementsIn:(NSData *)data {
    if (!data.length) return @[];
    TMExtParser *p = [[TMExtParser alloc] init];
    p->_elements = [NSMutableArray array];
    NSXMLParser *xml = [[NSXMLParser alloc] initWithData:data];
    xml.delegate = p;
    [xml parse];
    return p->_elements;
}

- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)name
       namespaceURI:(NSString *)ns
      qualifiedName:(NSString *)qname
         attributes:(NSDictionary *)attrs {
    [_elements addObject:@[ name, attrs ?: @{} ]];
}

+ (TMStreamSet *)parseStreams:(NSData *)data {
    TMStreamSet *set = nil;
    NSMutableArray *streams = [NSMutableArray array];
    NSString *pendingAudio = nil, *pendingDownload = nil;
    BOOL pendingDubbed = NO;
    for (NSArray *el in [self elementsIn:data]) {
        NSString *name = el[0];
        NSDictionary *a = el[1];
        if ([name isEqualToString:@"tm:streams"]) {
            set = [[TMStreamSet alloc] init];
            set.videoID = a[@"video_id"] ?: @"";
            set.availableIn = [a[@"available_in"] integerValue];
            set.expire = [a[@"expire"] longLongValue];
            set.proxied = [a[@"proxy"] isEqualToString:@"1"];
        } else if ([name isEqualToString:@"tm:audio"]) {
            pendingAudio = a[@"url"];
        } else if ([name isEqualToString:@"tm:download"]) {
            pendingDownload = a[@"url"];
            pendingDubbed = [a[@"dubbed"] isEqualToString:@"1"];
        } else if ([name isEqualToString:@"tm:stream"] && [a[@"url"] length]) {
            TMStream *s = [[TMStream alloc] init];
            s.quality = [a[@"quality"] integerValue];
            s.kind = a[@"kind"] ?: @"mp4";
            s.url = a[@"url"];
            s.bandwidth = [a[@"bandwidth"] longLongValue];
            [streams addObject:s];
        }
    }
    set.streams = streams;
    set.audioURL = pendingAudio;
    set.downloadURL = pendingDownload;
    set.downloadDubbed = pendingDubbed;
    return set.streams.count ? set : nil;
}

+ (TMPing *)parsePing:(NSData *)data {
    for (NSArray *el in [self elementsIn:data]) {
        if ([el[0] isEqualToString:@"tm:ping"]) {
            NSDictionary *a = el[1];
            TMPing *p = [[TMPing alloc] init];
            p.server = a[@"server"] ?: @"";
            p.ytdlp = a[@"yt_dlp"] ?: @"";
            p.deno = a[@"deno"] ?: @"";
            p.auth = a[@"auth"] ?: @"";
            p.proxy = a[@"proxy"] ?: @"off";
            return p;
        }
    }
    return nil;
}

+ (NSDictionary *)attributesOf:(NSString *)name in:(NSData *)data {
    for (NSArray *el in [self elementsIn:data]) {
        if ([el[0] isEqualToString:name]) return el[1];
    }
    return nil;
}

+ (NSString *)errorMessageIn:(NSData *)data {
    for (NSArray *el in [self elementsIn:data]) {
        if ([el[0] isEqualToString:@"tm:error"]) {
            NSString *m = el[1][@"message"];
            return m.length ? m : @"Máy chủ báo lỗi.";
        }
    }
    return nil;
}

@end
