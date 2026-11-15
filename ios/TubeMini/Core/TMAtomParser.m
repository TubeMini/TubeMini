#import "TMAtomParser.h"

@implementation TMAtomParser {
    NSMutableArray *_entries;
    NSString *_next;
    NSMutableDictionary *_cur; // fields of the entry being read
    NSMutableString *_text;
    BOOL _inEntry, _inAuthor, _inMediaGroup;
}

+ (NSDate *)dateFromString:(NSString *)s {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    });
    if (s.length < 19) return nil;
    NSDate *d;
    @synchronized(fmt) {
        d = [fmt dateFromString:s];
    }
    return [d timeIntervalSince1970] > 86400 ? d : nil;
}

+ (TMFeed *)parseFeed:(NSData *)data {
    TMAtomParser *p = [[TMAtomParser alloc] init];
    p->_entries = [NSMutableArray array];
    p->_text = [NSMutableString string];
    if (data.length) {
        NSXMLParser *xml = [[NSXMLParser alloc] initWithData:data];
        xml.delegate = p;
        xml.shouldProcessNamespaces = NO;
        [xml parse];
    }
    TMFeed *feed = [[TMFeed alloc] init];
    feed.entries = [p->_entries copy];
    feed.nextURL = p->_next;
    return feed;
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)name
       namespaceURI:(NSString *)ns
      qualifiedName:(NSString *)qname
         attributes:(NSDictionary *)attrs {
    [_text setString:@""];
    if ([name isEqualToString:@"entry"]) {
        _inEntry = YES;
        _cur = [NSMutableDictionary dictionary];
        return;
    }
    if (!_inEntry) {
        if ([name isEqualToString:@"link"] && [attrs[@"rel"] isEqualToString:@"next"] && attrs[@"href"]) {
            _next = attrs[@"href"];
        }
        return;
    }
    if ([name isEqualToString:@"author"]) {
        _inAuthor = YES;
    } else if ([name isEqualToString:@"media:group"]) {
        _inMediaGroup = YES;
    } else if ([name isEqualToString:@"category"]) {
        NSString *scheme = attrs[@"scheme"], *term = attrs[@"term"];
        NSRange hash = [term rangeOfString:@"#" options:NSBackwardsSearch];
        if ([scheme hasSuffix:@"#kind"] && hash.location != NSNotFound) {
            _cur[@"kind"] = [term substringFromIndex:hash.location + 1];
        }
    } else if ([name isEqualToString:@"yt:duration"] && attrs[@"seconds"]) {
        _cur[@"duration"] = attrs[@"seconds"];
    } else if ([name isEqualToString:@"yt:statistics"] && attrs[@"viewCount"]) {
        _cur[@"views"] = attrs[@"viewCount"];
    } else if ([name isEqualToString:@"yt:channelStatistics"] && attrs[@"subscriberCount"]) {
        _cur[@"subscribers"] = attrs[@"subscriberCount"];
    } else if ([name isEqualToString:@"gd:feedLink"] && attrs[@"countHint"] && !_cur[@"countHint"]) {
        _cur[@"countHint"] = attrs[@"countHint"];
    } else if ([name isEqualToString:@"tm:position"] && attrs[@"seconds"]) {
        _cur[@"position"] = attrs[@"seconds"];
    } else if ([name isEqualToString:@"media:thumbnail"] && attrs[@"url"] && !_cur[@"thumb"]) {
        _cur[@"thumb"] = attrs[@"url"];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [_text appendString:string];
}

- (void)parser:(NSXMLParser *)parser
    didEndElement:(NSString *)name
     namespaceURI:(NSString *)ns
    qualifiedName:(NSString *)qname {
    if (!_inEntry) return;
    NSString *text = [_text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name isEqualToString:@"entry"]) {
        id model = [self modelFromEntry:_cur];
        if (model) [_entries addObject:model];
        _inEntry = _inAuthor = _inMediaGroup = NO;
        _cur = nil;
    } else if ([name isEqualToString:@"author"]) {
        _inAuthor = NO;
    } else if ([name isEqualToString:@"media:group"]) {
        _inMediaGroup = NO;
    } else if (_inAuthor && [name isEqualToString:@"name"]) {
        _cur[@"authorName"] = text;
    } else if (_inAuthor && [name isEqualToString:@"yt:userId"]) {
        _cur[@"authorID"] = text;
    } else if ([name isEqualToString:@"title"] && !_inMediaGroup) {
        _cur[@"title"] = text;
    } else if ([name isEqualToString:@"published"]) {
        _cur[@"published"] = text;
    } else if ([name isEqualToString:@"yt:videoid"]) {
        _cur[@"videoID"] = text;
    } else if ([name isEqualToString:@"media:description"]) {
        _cur[@"description"] = text;
    } else if ([name isEqualToString:@"summary"]) {
        _cur[@"summary"] = text;
    } else if ([name isEqualToString:@"content"]) {
        _cur[@"content"] = text;
    } else if ([name isEqualToString:@"yt:channelId"]) {
        _cur[@"channelID"] = text;
    } else if ([name isEqualToString:@"yt:replyCount"]) {
        _cur[@"replies"] = text;
    } else if ([name isEqualToString:@"yt:playlistId"]) {
        _cur[@"playlistID"] = text;
    } else if ([name isEqualToString:@"yt:countHint"]) {
        _cur[@"countHint"] = text;
    } else if ([name isEqualToString:@"tm:watched"]) {
        _cur[@"watched"] = text;
    }
    [_text setString:@""];
}

#pragma mark - Models

static NSString *str(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

- (id)modelFromEntry:(NSDictionary *)e {
    NSString *kind = str(e, @"kind");
    if ([kind isEqualToString:@"video"] || (!kind.length && str(e, @"videoID").length)) {
        TMVideo *v = [[TMVideo alloc] init];
        v.videoID = str(e, @"videoID");
        if (!v.videoID.length) return nil;
        v.title = str(e, @"title");
        v.author = str(e, @"authorName");
        v.authorID = str(e, @"authorID");
        v.descriptionText = str(e, @"description");
        v.duration = [str(e, @"duration") integerValue];
        v.views = [str(e, @"views") longLongValue];
        v.published = [TMAtomParser dateFromString:str(e, @"published")];
        v.position = [str(e, @"position") integerValue];
        v.watched = [TMAtomParser dateFromString:str(e, @"watched")];
        return v;
    }
    if ([kind isEqualToString:@"channel"]) {
        TMChannel *c = [[TMChannel alloc] init];
        c.channelID = str(e, @"channelID").length ? str(e, @"channelID") : str(e, @"authorID");
        if (!c.channelID.length) return nil;
        c.name = str(e, @"title");
        c.summary = str(e, @"summary");
        c.avatarURL = str(e, @"thumb");
        c.subscribers = [str(e, @"subscribers") longLongValue];
        c.videoCount = [str(e, @"countHint") longLongValue];
        return c;
    }
    if ([kind isEqualToString:@"comment"]) {
        TMComment *c = [[TMComment alloc] init];
        c.author = str(e, @"authorName");
        c.authorID = str(e, @"authorID");
        c.text = str(e, @"content");
        c.published = [TMAtomParser dateFromString:str(e, @"published")];
        c.replies = [str(e, @"replies") integerValue];
        return c.text.length ? c : nil;
    }
    if ([kind isEqualToString:@"playlistLink"]) {
        TMPlaylist *p = [[TMPlaylist alloc] init];
        p.playlistID = str(e, @"playlistID");
        if (!p.playlistID.length) return nil;
        p.title = str(e, @"title");
        p.author = str(e, @"authorName");
        p.count = [str(e, @"countHint") integerValue];
        p.thumbnailURL = str(e, @"thumb");
        return p;
    }
    return nil;
}

@end
