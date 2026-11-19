#import "TMVideoViewController.h"
#import "TMAlert.h"
#import "TMCells.h"
#import "TMChannelViewController.h"
#import "TMCompat.h"
#import "TMDownloads.h"
#import "TMFormat.h"
#import "TMGlass.h"
#import "TMImageLoader.h"
#import "TMLibrary.h"
#import "TMPlayer.h"
#import "TMTheme.h"

static const CGFloat kChannelAvatar = 40;

@implementation TMVideoViewController {
    TMVideo *_video;
    TMChannel *_channel; // fetched for the avatar and subscriber count
    UIView *_header;
    UIImageView *_thumb, *_avatar, *_descBack;
    TMGlassButton *_playOverlay;
    UILabel *_title, *_meta, *_channelName, *_channelMeta, *_desc;
    UIControl *_channelRow;
    TMPill *_subscribe, *_playPill, *_listenPill, *_downloadPill, *_qualityPill;
    UIScrollView *_actions;
    TMSegmentedControl *_segment;
    BOOL _descExpanded, _subBusy;
    NSInteger _quality;
    NSInteger _resumeAt; // seconds, from the watch history; 0 = from the start
    BOOL _loadingChoices;
    CGFloat _laidOutWidth;
    CGSize _thumbSize;
}

- (instancetype)initWithVideo:(TMVideo *)video {
    if ((self = [super initWithTitle:@"" firstPage:nil])) {
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

static UILabel *headerLabel(UIFont *font, NSInteger lines) {
    UILabel *l = [[UILabel alloc] init];
    l.font = font;
    l.numberOfLines = lines;
    l.backgroundColor = [UIColor clearColor];
    l.lineBreakMode = TMLineBreakWord;
    return l;
}

- (void)buildHeader {
    _header = [[UIView alloc] initWithFrame:CGRectZero];
    _thumb = [[UIImageView alloc] init];
    _thumb.userInteractionEnabled = YES;
    [_thumb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(play)]];
    [_header addSubview:_thumb];
    _playOverlay = [TMGlassButton buttonWithIcon:@"play" target:self action:@selector(play)];
    _playOverlay.iconSize = 28;
    _playOverlay.glassInset = 0;
    _playOverlay.frame = CGRectMake(0, 0, 68, 68);
    [_header addSubview:_playOverlay];

    _title = headerLabel(TMFontBold(TMIsPhone() ? 18 : 20), 0);
    [_header addSubview:_title];
    _meta = headerLabel(TMFontRegular(13), 2);
    [_header addSubview:_meta];

    _channelRow = [[UIControl alloc] init];
    [_channelRow addTarget:self action:@selector(openChannel) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_channelRow];
    _avatar = [[UIImageView alloc] init];
    _avatar.userInteractionEnabled = NO;
    [_channelRow addSubview:_avatar];
    _channelName = headerLabel(TMFontMedium(15), 1);
    _channelName.lineBreakMode = TMLineBreakTail;
    [_channelRow addSubview:_channelName];
    _channelMeta = headerLabel(TMFontRegular(12.5), 1);
    _channelMeta.lineBreakMode = TMLineBreakTail;
    [_channelRow addSubview:_channelMeta];
    _subscribe = [TMPill pillWithTitle:@"Theo dõi" icon:nil style:TMPillStyleInverse target:self action:@selector(toggleSubscribe)];
    [_header addSubview:_subscribe];

    _actions = [[UIScrollView alloc] init];
    _actions.showsHorizontalScrollIndicator = NO;
    _actions.alwaysBounceHorizontal = YES;
    _actions.scrollsToTop = NO;
    [_header addSubview:_actions];
    _playPill = [TMPill pillWithTitle:@"Phát" icon:@"play" style:TMPillStyleBrand target:self action:@selector(play)];
    _listenPill = [TMPill pillWithTitle:@"Chỉ nghe" icon:@"headphones" style:TMPillStyleGray target:self action:@selector(listen)];
    _downloadPill = [TMPill pillWithTitle:@"Tải về" icon:@"download" style:TMPillStyleGray target:self action:@selector(download)];
    _qualityPill = [TMPill pillWithTitle:@"" icon:@"hd" style:TMPillStyleGray target:self action:@selector(chooseQuality)];
    for (TMPill *p in @[ _playPill, _listenPill, _downloadPill, _qualityPill ]) [_actions addSubview:p];

    _descBack = [[UIImageView alloc] init];
    _descBack.userInteractionEnabled = YES;
    [_descBack addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDescription)]];
    [_header addSubview:_descBack];
    _desc = headerLabel(TMFontRegular(14), 4);
    [_descBack addSubview:_desc];

    _segment = [[TMSegmentedControl alloc] initWithItems:@[ @"Video liên quan", @"Bình luận" ]];
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
    _channelName.textColor = t.text;
    _channelMeta.textColor = t.secondaryText;
    _desc.textColor = t.text;
    _descBack.image = TMRoundImage(t.elevated, 12);
    [self styleSubscribe];
}

- (void)styleSubscribe {
    if (!_subscribe) return;
    BOOL subscribed = [[TMLibrary shared] isSubscribed:_video.authorID];
    _subscribe.pillStyle = subscribed ? TMPillStyleGray : TMPillStyleInverse;
    _subscribe.title = _subBusy ? @"…" : (subscribed ? @"Đã theo dõi" : @"Theo dõi");
    [self layoutHeaderForce:YES];
}

- (void)updateDownloadTitle {
    TMDownload *x = [[TMDownloads shared] itemFor:_video.videoID];
    NSString *title = @"Tải về";
    NSString *icon = @"download";
    if (x.state == TMDownloadDone) {
        title = @"Đã tải";
        icon = @"check";
    } else if (x.state == TMDownloadFailed) {
        title = @"Tải lại";
    } else if (x.state == TMDownloadRunning && x.total > 0) {
        title = [NSString stringWithFormat:@"%d%%", (int)(100 * x.received / x.total)];
    } else if (x) {
        title = @"Đang chờ…";
    }
    if ([title isEqualToString:[_downloadPill titleForState:UIControlStateNormal]]) return;
    _downloadPill.title = title;
    _downloadPill.iconName = icon;
    [self layoutActions];
}

- (void)updatePlayTitle {
    _playPill.title = _resumeAt > 0 ? [NSString stringWithFormat:@"Xem tiếp %@", [TMFormat duration:_resumeAt]] : @"Phát";
    [self layoutActions];
}

- (void)updateQualityTitle {
    _qualityPill.title = [NSString stringWithFormat:@"%ldp", (long)_quality];
    [self layoutActions];
}

- (void)fillChannel {
    NSString *name = _video.author ?: @"";
    _channelName.text = name;
    _channelMeta.text = _channel.subscribers > 0 ? [NSString stringWithFormat:@"%@ người đăng ký", [TMFormat count:_channel.subscribers]] : @"";
    NSString *url = _channel.avatarURL.length ? _channel.avatarURL : [[TMLibrary shared] avatarForChannel:_video.authorID];
    CGSize size = CGSizeMake(kChannelAvatar, kChannelAvatar);
    [[TMImageLoader shared] setImageURL:url.length ? [NSURL URLWithString:url] : nil
                            onImageView:_avatar
                            placeholder:TMLetterAvatar(name, kChannelAvatar)
                                   size:size
                                 radius:kChannelAvatar / 2];
}

- (void)fillHeader {
    _title.text = _video.title;
    _meta.text = [TMFormat join:@[ [TMFormat views:_video.views], [TMFormat relativeDate:_video.published] ]];
    _desc.text = _video.descriptionText.length ? _video.descriptionText : @"";
    _desc.numberOfLines = _descExpanded ? 0 : 4;
    _channelRow.hidden = _subscribe.hidden = _video.authorID.length == 0 && _video.author.length == 0;
    _subscribe.hidden = _video.authorID.length == 0;
    [self fillChannel];
    [self styleSubscribe];
    [self updatePlayTitle];
    [self updateDownloadTitle];
    [self updateQualityTitle];
    _thumbSize = CGSizeZero; // reload the picture at the laid-out size
    [self layoutHeaderForce:YES];
}

- (void)layoutActions {
    CGFloat x = TMListMargin();
    for (TMPill *p in @[ _playPill, _listenPill, _downloadPill, _qualityPill ]) {
        p.frame = CGRectMake(x, 0, [p fittingWidth], 36);
        x += p.frame.size.width + 8;
    }
    _actions.contentSize = CGSizeMake(x - 8 + TMListMargin(), 36);
}

/// Frame layout for the current width; re-assigning tableHeaderView applies the new height.
- (void)layoutHeaderForce:(BOOL)force {
    if (!_header) return;
    CGFloat W = self.tableView.bounds.size.width;
    if (!force && W == _laidOutWidth) return;
    _laidOutWidth = W;
    CGFloat m = TMListMargin(), inner = W - 2 * m;
    // At most 720 pt wide, and 60% of the height (an iPhone on its side would see only the picture)
    CGFloat H = self.tableView.bounds.size.height, tw = MIN(inner, 720);
    if (H > 0) tw = MIN(tw, floor(H * 0.6 * 16 / 9));
    CGFloat th = floor(tw * 9 / 16);
    _thumb.frame = CGRectMake(floor((W - tw) / 2), 4, tw, th);
    if (!CGSizeEqualToSize(_thumbSize, _thumb.frame.size)) {
        _thumbSize = _thumb.frame.size;
        NSURL *hq = [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", _video.videoID]];
        [[TMImageLoader shared] setImageURL:hq onImageView:_thumb size:_thumbSize radius:TMIsPhone() ? 14 : 18];
    }
    _playOverlay.center = CGPointMake(CGRectGetMidX(_thumb.frame), CGRectGetMidY(_thumb.frame));
    CGFloat y = CGRectGetMaxY(_thumb.frame) + 14;
    CGSize ts = [_title.text sizeWithFont:_title.font constrainedToSize:CGSizeMake(inner, 200) lineBreakMode:TMLineBreakWord];
    _title.frame = CGRectMake(m, y, inner, ceil(ts.height));
    y += ceil(ts.height) + 4;
    _meta.frame = CGRectMake(m, y, inner, 17);
    y += 17 + 14;

    if (!_channelRow.hidden) {
        CGFloat sw = _subscribe.hidden ? 0 : [_subscribe fittingWidth];
        _subscribe.frame = CGRectMake(W - m - sw, y + 2, sw, 36);
        _channelRow.frame = CGRectMake(m, y, inner - sw - 10, kChannelAvatar);
        _avatar.frame = CGRectMake(0, 0, kChannelAvatar, kChannelAvatar);
        CGFloat nx = kChannelAvatar + 10, nw = _channelRow.bounds.size.width - nx;
        BOOL hasMeta = _channelMeta.text.length > 0;
        _channelName.frame = CGRectMake(nx, hasMeta ? 2 : 10, nw, 19);
        _channelMeta.frame = CGRectMake(nx, 22, nw, 16);
        _channelMeta.hidden = !hasMeta;
        y += kChannelAvatar + 14;
    }

    _actions.frame = CGRectMake(0, y, W, 36);
    [self layoutActions];
    y += 36 + 14;

    if (_desc.text.length) {
        CGFloat maxH = _descExpanded ? 3000 : 4 * _desc.font.lineHeight + 2;
        CGSize ds = [_desc.text sizeWithFont:_desc.font constrainedToSize:CGSizeMake(inner - 24, maxH) lineBreakMode:TMLineBreakWord];
        _descBack.hidden = NO;
        _descBack.frame = CGRectMake(m, y, inner, ceil(ds.height) + 22);
        _desc.frame = CGRectMake(12, 11, inner - 24, ceil(ds.height));
        y += _descBack.frame.size.height + 14;
    } else {
        _descBack.hidden = YES;
    }
    _segment.frame = CGRectMake(m, y, MIN(inner, 420), 34);
    y += 34 + 10;
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
                         BOOL newChannel = ![full.authorID isEqualToString:self->_video.authorID];
                         self->_video = full;
                         [self fillHeader];
                         if (newChannel) [self loadChannel];
                     }];
    [self loadChannel];
    [[TMAPIClient shared] positionOf:_video.videoID
                          completion:^(NSInteger position, NSInteger duration) {
                              self->_resumeAt = [TMLibrary resumePositionFor:position duration:duration];
                              [self updatePlayTitle];
                          }];
}

/// The channel's avatar and subscriber count for the channel row.
- (void)loadChannel {
    NSString *cid = _video.authorID;
    if (!cid.length) return;
    [[TMAPIClient shared] channel:cid
                       completion:^(TMChannel *c, NSString *error) {
                           if (!c || ![cid isEqualToString:self->_video.authorID]) return;
                           self->_channel = c;
                           [[TMLibrary shared] rememberChannel:c];
                           [self fillChannel];
                           [self layoutHeaderForce:YES];
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
        // Already on the device: play the saved copy (works without network)
        [[TMPlayer shared] playFile:x.filePath video:_video startAt:_resumeAt from:self];
    } else {
        [TMAlert showTitle:@"Đang tải" message:@"Xem tiến độ ở tab “Đã tải”." button:@"OK"];
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
    _downloadPill.title = @"…";
    [self loadDownloadChoices:^(NSArray *choices, NSString *error) {
        self->_loadingChoices = NO;
        self->_downloadPill.title = @"";
        [self updateDownloadTitle];
        if (error) {
            [TMAlert showTitle:@"Không tải được" message:error button:@"Đóng"];
            return;
        }
        NSMutableArray *titles = [NSMutableArray array];
        for (NSDictionary *c in choices) {
            long long bytes = [c[@"bytes"] longLongValue];
            [titles addObject:bytes > 0 ? [NSString stringWithFormat:@"%@ · khoảng %lld MB", c[@"title"], MAX(bytes >> 20, 1LL)] : c[@"title"]];
        }
        [TMAlert sheetWithTitle:@"Tải về để xem khi không có mạng"
                        buttons:titles
               destructiveIndex:-1
                        handler:^(NSInteger i) {
                            if (i >= 0 && i < (NSInteger)choices.count) [self startDownload:choices[(NSUInteger)i]];
                        }];
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
    [TMAlert sheetWithTitle:@"Chất lượng phát"
                    buttons:@[ @"360p (nhẹ, ổn định)", @"720p (HD)", @"1080p (Full HD)" ]
           destructiveIndex:-1
                    handler:^(NSInteger i) {
                        NSArray *qualities = [TMAPIClient qualities];
                        if (i < 0 || i >= (NSInteger)qualities.count) return;
                        self->_quality = [qualities[(NSUInteger)i] integerValue];
                        [self updateQualityTitle];
                    }];
}

- (void)openChannel {
    if (!_video.authorID.length) return;
    TMChannelViewController *c = _channel ? [[TMChannelViewController alloc] initWithChannel:_channel]
                                           : [[TMChannelViewController alloc] initWithChannelID:_video.authorID name:_video.author];
    [self.navigationController pushViewController:c animated:YES];
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
                                   [TMAlert showTitle:subscribe ? @"Không theo dõi được" : @"Không bỏ theo dõi được" message:error button:@"Đóng"];
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
