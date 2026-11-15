#import "TMVideoViewController.h"
#import "TMFormat.h"
#import "TMChannelViewController.h"
#import "TMDownloads.h"
#import "TMImageLoader.h"
#import "TMLibrary.h"
#import "TMPlayer.h"
#import "TMTheme.h"

@implementation TMVideoViewController {
    TMVideo *_video;
    UIView *_header;
    UIImageView *_thumb;
    UIButton *_playOverlay, *_playButton, *_qualityButton, *_channelButton, *_subscribeButton, *_listenButton, *_downloadButton;
    UILabel *_title, *_meta, *_desc;
    UISegmentedControl *_segment;
    BOOL _descExpanded, _subBusy;
    NSInteger _quality;
    NSInteger _resumeAt; // seconds, from the watch history; 0 = from the start
    NSArray *_downloadChoices; // @{title, quality, hls, bytes} shown in the sheet
    BOOL _loadingChoices;
    CGFloat _laidOutWidth;
}

- (instancetype)initWithVideo:(TMVideo *)video {
    if ((self = [super initWithTitle:@"Video" firstPage:nil])) {
        _video = video;
        _quality = [TMAPIClient shared].preferredQuality;
        [self useSection:0];
    }
    return self;
}

- (TMVideo *)video {
    return _video;
}

- (void)useSection:(NSInteger)section {
    NSString *vid = _video.videoID;
    if (section == 1) {
        self.emptyMessage = @"Chưa có bình luận (hoặc video đã tắt bình luận).";
        self.firstPage = ^(TMFeedBlock done) { [[TMAPIClient shared] comments:vid completion:done]; };
    } else {
        self.emptyMessage = @"Không có video liên quan.";
        self.firstPage = ^(TMFeedBlock done) { [[TMAPIClient shared] related:vid completion:done]; };
    }
}

- (void)showSection:(NSInteger)section {
    _segment.selectedSegmentIndex = section;
    [self useSection:section];
    [self reload];
}

#pragma mark - Header

+ (UIImage *)playImage {
    CGFloat d = 76;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(d, d), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, d, d));
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextMoveToPoint(ctx, d * 0.39, d * 0.28);
    CGContextAddLineToPoint(ctx, d * 0.39, d * 0.72);
    CGContextAddLineToPoint(ctx, d * 0.74, d * 0.5);
    CGContextFillPath(ctx);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static UIButton *makeButton(NSString *title, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; // styled by TMTheme (rounded-rect is always white)
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildHeader {
    _header = [[UIView alloc] initWithFrame:CGRectZero];
    _header.backgroundColor = [UIColor whiteColor];
    _thumb = [[UIImageView alloc] init];
    _thumb.contentMode = UIViewContentModeScaleAspectFill;
    _thumb.clipsToBounds = YES;
    _thumb.backgroundColor = [UIColor blackColor];
    [_header addSubview:_thumb];
    _playOverlay = [UIButton buttonWithType:UIButtonTypeCustom];
    [_playOverlay setImage:[TMVideoViewController playImage] forState:UIControlStateNormal];
    [_playOverlay addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_playOverlay];

    _title = [[UILabel alloc] init];
    _title.font = [UIFont boldSystemFontOfSize:20];
    _title.numberOfLines = 0;
    _title.backgroundColor = [UIColor clearColor];
    [_header addSubview:_title];
    _meta = [[UILabel alloc] init];
    _meta.font = [UIFont systemFontOfSize:15];
    _meta.textColor = [UIColor darkGrayColor];
    _meta.numberOfLines = 2;
    _meta.backgroundColor = [UIColor clearColor];
    [_header addSubview:_meta];

    _playButton = makeButton(@"▶ Phát", self, @selector(play));
    _qualityButton = makeButton(@"", self, @selector(chooseQuality));
    _channelButton = makeButton(@"Kênh", self, @selector(openChannel));
    _subscribeButton = makeButton(@"", self, @selector(toggleSubscribe));
    _listenButton = makeButton(@"♫ Chỉ nghe", self, @selector(listen));
    _downloadButton = makeButton(@"", self, @selector(download));
    [_header addSubview:_listenButton];
    [_header addSubview:_downloadButton];
    [_header addSubview:_playButton];
    [_header addSubview:_qualityButton];
    [_header addSubview:_channelButton];
    [_header addSubview:_subscribeButton];

    _desc = [[UILabel alloc] init];
    _desc.font = [UIFont systemFontOfSize:14];
    _desc.textColor = [UIColor darkGrayColor];
    _desc.backgroundColor = [UIColor clearColor];
    _desc.userInteractionEnabled = YES;
    [_desc addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDescription)]];
    [_header addSubview:_desc];

    _segment = [[UISegmentedControl alloc] initWithItems:@[ @"Video liên quan", @"Bình luận" ]];
    _segment.segmentedControlStyle = UISegmentedControlStyleBar;
    _segment.selectedSegmentIndex = 0;
    [_segment addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    [_header addSubview:_segment];
    [self applyTheme];
}

- (void)applyTheme {
    [super applyTheme];
    TMTheme *t = [TMTheme current];
    _header.backgroundColor = t.background;
    _title.textColor = t.text;
    _meta.textColor = t.secondaryText;
    _desc.textColor = t.secondaryText;
    for (UIButton *b in @[ _playButton ?: [NSNull null], _qualityButton ?: [NSNull null], _channelButton ?: [NSNull null],
                          _listenButton ?: [NSNull null], _downloadButton ?: [NSNull null] ]) {
        if ([b isKindOfClass:[UIButton class]]) [t styleButton:b];
    }
    _segment.tintColor = t.dark ? [UIColor colorWithWhite:0.28 alpha:1] : [UIColor colorWithRed:0.62 green:0.08 blue:0.08 alpha:1];
    [self styleSubscribe];
}

- (void)styleSubscribe {
    if (!_subscribeButton) return;
    [[TMTheme current] styleSubscribeButton:_subscribeButton subscribed:[[TMLibrary shared] isSubscribed:_video.authorID] busy:_subBusy];
}

- (void)updateDownloadTitle {
    TMDownload *x = [[TMDownloads shared] itemFor:_video.videoID];
    NSString *title = @"⬇ Tải về";
    if (x.state == TMDownloadDone) {
        title = @"✓ Đã tải";
    } else if (x.state == TMDownloadFailed) {
        title = @"⬇ Tải lại";
    } else if (x.state == TMDownloadRunning && x.total > 0) {
        title = [NSString stringWithFormat:@"⬇ %d%%", (int)(100 * x.received / x.total)];
    } else if (x) {
        title = @"⬇ Đang chờ…";
    }
    [_downloadButton setTitle:title forState:UIControlStateNormal];
}

- (void)updatePlayTitle {
    NSString *title = _resumeAt > 0 ? [NSString stringWithFormat:@"▶ Xem tiếp %@", [TMFormat duration:_resumeAt]] : @"▶ Phát";
    [_playButton setTitle:title forState:UIControlStateNormal];
}

- (void)fillHeader {
    _title.text = _video.title;
    _meta.text = [TMFormat join:@[ _video.author ?: @"", [TMFormat views:_video.views], [TMFormat relativeDate:_video.published] ]];
    _desc.text = _video.descriptionText.length ? _video.descriptionText : @"";
    _desc.numberOfLines = _descExpanded ? 0 : 4;
    [_qualityButton setTitle:[NSString stringWithFormat:@"Chất lượng: %ldp", (long)_quality] forState:UIControlStateNormal];
    _channelButton.hidden = _video.authorID.length == 0;
    _subscribeButton.hidden = _channelButton.hidden;
    [self styleSubscribe];
    [self updatePlayTitle];
    [self updateDownloadTitle];
    NSURL *hq = [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", _video.videoID]];
    [[TMImageLoader shared] setImageURL:hq onImageView:_thumb placeholder:nil size:CGSizeMake(480, 360)];
    [self layoutHeaderForce:YES];
}

/// Frame layout for the current width; re-assigning tableHeaderView applies the new height.
- (void)layoutHeaderForce:(BOOL)force {
    CGFloat W = self.tableView.bounds.size.width;
    if (!force && W == _laidOutWidth) return;
    _laidOutWidth = W;
    CGFloat pad = 15, inner = W - 2 * pad;
    CGFloat tw = MIN(inner, 600), th = floor(tw * 9 / 16);
    _thumb.frame = CGRectMake(floor((W - tw) / 2), 10, tw, th);
    _playOverlay.frame = CGRectMake(CGRectGetMidX(_thumb.frame) - 38, CGRectGetMidY(_thumb.frame) - 38, 76, 76);
    CGFloat y = CGRectGetMaxY(_thumb.frame) + 12;
    CGSize ts = [_title.text sizeWithFont:_title.font constrainedToSize:CGSizeMake(inner, 120) lineBreakMode:NSLineBreakByWordWrapping];
    _title.frame = CGRectMake(pad, y, inner, ts.height);
    y += ts.height + 4;
    CGSize ms = [_meta.text sizeWithFont:_meta.font constrainedToSize:CGSizeMake(inner, 40) lineBreakMode:NSLineBreakByWordWrapping];
    _meta.frame = CGRectMake(pad, y, inner, ms.height);
    y += ms.height + 10;
    // Two rows: watching (play, listen, quality), then download / channel / subscribe
    CGFloat bw = floor(MIN(230, (inner - 20) / 3));
    _playButton.frame = CGRectMake(pad, y, bw, 40);
    _listenButton.frame = CGRectMake(pad + bw + 10, y, bw, 40);
    _qualityButton.frame = CGRectMake(pad + 2 * (bw + 10), y, bw, 40);
    y += 50;
    _downloadButton.frame = CGRectMake(pad, y, bw, 40);
    _channelButton.frame = CGRectMake(pad + bw + 10, y, bw, 40);
    _subscribeButton.frame = CGRectMake(pad + 2 * (bw + 10), y, bw, 40);
    y += 52;
    if (_desc.text.length) {
        CGFloat maxH = _descExpanded ? 2000 : 4 * _desc.font.lineHeight + 2;
        CGSize ds = [_desc.text sizeWithFont:_desc.font constrainedToSize:CGSizeMake(inner, maxH) lineBreakMode:NSLineBreakByWordWrapping];
        _desc.frame = CGRectMake(pad, y, inner, ds.height);
        y += ds.height + 12;
    } else {
        _desc.frame = CGRectZero;
    }
    _segment.frame = CGRectMake(pad, y, inner, 32);
    y += 32 + 10;
    _header.frame = CGRectMake(0, 0, W, y);
    self.tableView.tableHeaderView = _header;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildHeader];
    [self fillHeader];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(styleSubscribe)
                                                 name:TMSubscriptionsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(historyChanged:)
                                                 name:TMHistoryDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateDownloadTitle)
                                                 name:TMDownloadsDidChangeNotification
                                               object:nil];
    // List entries (related videos) have no description: fetch the full entry once
    [[TMAPIClient shared] video:_video.videoID
                     completion:^(TMVideo *full, NSString *error) {
                         if (!full) return;
                         self->_video = full;
                         [self fillHeader];
                     }];
    [[TMAPIClient shared] positionOf:_video.videoID
                          completion:^(NSInteger position, NSInteger duration) {
                              self->_resumeAt = [TMLibrary resumePositionFor:position duration:duration];
                              [self updatePlayTitle];
                          }];
}

/// The player saved a position for this video: "Xem tiếp" follows it without asking the server.
- (void)historyChanged:(NSNotification *)n {
    if (![n.userInfo[@"videoID"] isEqualToString:_video.videoID]) return;
    _resumeAt = [TMLibrary resumePositionFor:[n.userInfo[@"position"] integerValue] duration:[n.userInfo[@"duration"] integerValue]];
    [self updatePlayTitle];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self layoutHeaderForce:NO];
}

#pragma mark - Actions

- (void)play {
    [[TMPlayer shared] playVideo:_video quality:_quality startAt:_resumeAt from:self];
}

- (void)listen {
    [[TMPlayer shared] playAudioOf:_video startAt:_resumeAt from:self];
}

- (void)download {
    TMDownloads *d = [TMDownloads shared];
    TMDownload *x = [d itemFor:_video.videoID];
    // (nil first: a nil item's state reads as 0 = TMDownloadWaiting)
    if (x.state == TMDownloadFailed) {
        [d retry:_video.videoID];
    } else if (!x) {
        [self chooseDownload];
    } else if (x.state == TMDownloadDone) {
        // Already on the iPad: play the saved copy (works without network)
        [[TMPlayer shared] playFile:x.filePath video:_video startAt:_resumeAt from:self];
    } else {
        [[[UIAlertView alloc] initWithTitle:@"Đang tải"
                                    message:@"Xem tiến độ ở tab “Đã tải”."
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    }
}

/// The levels this video can be saved at, with their size: 360p MP4 (or 360p HLS with the original audio
/// when the MP4 is AI-dubbed), and the HLS levels above.
- (void)loadDownloadChoices:(void (^)(NSArray *choices, NSString *error))done {
    NSInteger duration = _video.duration;
    [[TMAPIClient shared] streams:_video.videoID
                            fresh:NO
                       completion:^(TMStreamSet *set, NSString *error) {
                           if (error) {
                               done(nil, error);
                               return;
                           }
                           NSMutableArray *choices = [NSMutableArray array];
                           BOOL mp4 = set.downloadURL.length > 0 && !set.downloadDubbed;
                           if (mp4) {
                               // itag 18 is about 0.6 Mbit/s
                               [choices addObject:@{ @"quality" : @360, @"hls" : @NO, @"bytes" : @(duration * 75000LL), @"title" : @"360p (MP4)" }];
                           }
                           for (TMStream *s in set.streams) {
                               if (![s.kind isEqualToString:@"hls"] || (mp4 && s.quality <= 360)) continue;
                               NSString *title = s.quality <= 360 ? @"360p (tiếng gốc)" : [NSString stringWithFormat:@"%ldp", (long)s.quality];
                               // BANDWIDTH is the peak: on average YouTube's HLS uses a bit over half of it
                               [choices addObject:@{ @"quality" : @(s.quality), @"hls" : @YES, @"bytes" : @(s.bandwidth * duration * 55 / 800),
                                                     @"title" : title }];
                           }
                           if (!choices.count && set.downloadURL.length) {
                               [choices addObject:@{ @"quality" : @360, @"hls" : @NO, @"bytes" : @(duration * 75000LL),
                                                     @"title" : @"360p (tiếng lồng AI)" }];
                           }
                           done(choices, choices.count ? nil : @"Video này không có bản nào tải về được.");
                       }];
}

- (void)startDownload:(NSDictionary *)choice {
    _video.position = _resumeAt; // the saved copy resumes there too
    [[TMDownloads shared] add:_video
                      quality:[choice[@"quality"] integerValue]
                          hls:[choice[@"hls"] boolValue]
                     estimate:[choice[@"bytes"] longLongValue]];
}

- (void)chooseDownload {
    if (_loadingChoices) return;
    _loadingChoices = YES;
    [_downloadButton setTitle:@"⬇ …" forState:UIControlStateNormal];
    [self loadDownloadChoices:^(NSArray *choices, NSString *error) {
        self->_loadingChoices = NO;
        [self updateDownloadTitle];
        if (error) {
            [[[UIAlertView alloc] initWithTitle:@"Không tải được" message:error delegate:nil cancelButtonTitle:@"Đóng"
                              otherButtonTitles:nil] show];
            return;
        }
        self->_downloadChoices = choices;
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Tải về để xem khi không có mạng"
                                                           delegate:self
                                                  cancelButtonTitle:nil
                                             destructiveButtonTitle:nil
                                                  otherButtonTitles:nil];
        sheet.tag = 2;
        for (NSDictionary *c in choices) {
            long long bytes = [c[@"bytes"] longLongValue];
            [sheet addButtonWithTitle:bytes > 0 ? [NSString stringWithFormat:@"%@ · khoảng %lld MB", c[@"title"], MAX(bytes >> 20, 1LL)]
                                                : c[@"title"]];
        }
        [sheet showFromRect:self->_downloadButton.frame inView:self->_header animated:YES];
    }];
}

- (void)downloadQuality:(NSInteger)quality {
    [self loadDownloadChoices:^(NSArray *choices, NSString *error) {
        NSDictionary *pick = nil;
        for (NSDictionary *c in choices) {
            if ([c[@"quality"] integerValue] <= quality && (!pick || [c[@"quality"] integerValue] > [pick[@"quality"] integerValue])) pick = c;
        }
        if (pick) [self startDownload:pick];
    }];
}

- (void)chooseQuality {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chất lượng phát"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"360p (nhẹ, ổn định)", @"720p (HD)", @"1080p (Full HD)", nil];
    [sheet showFromRect:_qualityButton.frame inView:_header animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == 2) {
        if (buttonIndex >= 0 && buttonIndex < (NSInteger)_downloadChoices.count) [self startDownload:_downloadChoices[(NSUInteger)buttonIndex]];
        _downloadChoices = nil;
        return;
    }
    NSArray *qualities = [TMAPIClient qualities];
    if (buttonIndex < 0 || buttonIndex >= (NSInteger)qualities.count) return;
    _quality = [qualities[(NSUInteger)buttonIndex] integerValue];
    [_qualityButton setTitle:[NSString stringWithFormat:@"Chất lượng: %ldp", (long)_quality] forState:UIControlStateNormal];
}

- (void)openChannel {
    if (!_video.authorID.length) return;
    [self.navigationController pushViewController:[[TMChannelViewController alloc] initWithChannelID:_video.authorID name:_video.author]
                                         animated:YES];
}

- (void)toggleSubscribe {
    NSString *cid = _video.authorID;
    if (_subBusy || !cid.length) return;
    BOOL subscribe = ![[TMLibrary shared] isSubscribed:cid];
    _subBusy = YES;
    [self styleSubscribe];
    [[TMLibrary shared] setSubscribed:subscribe
                            channelID:cid
                           completion:^(NSString *error) {
                               self->_subBusy = NO;
                               [self styleSubscribe];
                               if (error) {
                                   [[[UIAlertView alloc] initWithTitle:subscribe ? @"Không theo dõi được" : @"Không bỏ theo dõi được"
                                                               message:error
                                                              delegate:nil
                                                     cancelButtonTitle:@"Đóng"
                                                     otherButtonTitles:nil] show];
                               }
                           }];
}

- (void)toggleDescription {
    _descExpanded = !_descExpanded;
    _desc.numberOfLines = _descExpanded ? 0 : 4;
    [self layoutHeaderForce:YES];
}

- (void)segmentChanged {
    [self showSection:_segment.selectedSegmentIndex];
}

@end
