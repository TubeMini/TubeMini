#import "TMChannelViewController.h"
#import "TMAlert.h"
#import "TMCells.h"
#import "TMCompat.h"
#import "TMFormat.h"
#import "TMGlass.h"
#import "TMImageLoader.h"
#import "TMLibrary.h"
#import "TMTheme.h"
#import <QuartzCore/QuartzCore.h>

@implementation TMChannelViewController {
    TMChannel *_channel;
    UIView *_header;
    UIImageView *_avatar, *_descBack;
    UILabel *_name, *_meta, *_desc;
    TMPill *_subscribe;
    TMSegmentedControl *_segment;
    BOOL _descExpanded, _busy;
    CGFloat _laidOutWidth;
}

- (instancetype)initWithChannel:(TMChannel *)channel {
    if ((self = [super initWithTitle:@"" firstPage:nil])) {
        _channel = channel;
        [self useSection:0];
    }
    return self;
}

- (instancetype)initWithChannelID:(NSString *)channelID name:(NSString *)name {
    TMChannel *c = [[TMChannel alloc] init];
    c.channelID = channelID;
    c.name = name ?: @"";
    return [self initWithChannel:c];
}

- (TMChannel *)channel {
    return _channel;
}

- (void)useSection:(NSInteger)section {
    NSString *cid = _channel.channelID;
    if (section == 1) {
        self.emptyMessage = @"Kênh chưa có playlist.";
        self.firstPage = ^(TMFeedBlock done) { [[TMAPIClient shared] channelPlaylists:cid completion:done]; };
    } else {
        self.emptyMessage = @"Kênh chưa có video.";
        self.firstPage = ^(TMFeedBlock done) { [[TMAPIClient shared] uploads:cid completion:done]; };
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
    _avatar = [[UIImageView alloc] init];
    [_header addSubview:_avatar];
    _name = headerLabel(TMFontBold(TMIsPhone() ? 22 : 26), 2);
    [_header addSubview:_name];
    _meta = headerLabel(TMFontRegular(13.5), 2);
    [_header addSubview:_meta];
    _subscribe = [TMPill pillWithTitle:@"Theo dõi" icon:nil style:TMPillStyleInverse target:self action:@selector(toggleSubscribe)];
    [_header addSubview:_subscribe];
    _descBack = [[UIImageView alloc] init];
    _descBack.userInteractionEnabled = YES;
    [_descBack addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDescription)]];
    [_header addSubview:_descBack];
    _desc = headerLabel(TMFontRegular(14), 3);
    [_descBack addSubview:_desc];
    _segment = [[TMSegmentedControl alloc] initWithItems:@[ @"Video", @"Playlist" ]];
    [_segment addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    [_header addSubview:_segment];
    [self applyTheme];
}

- (void)applyTheme {
    [super applyTheme];
    TMTheme *t = [TMTheme current];
    _header.backgroundColor = t.background;
    _name.textColor = t.text;
    _meta.textColor = t.secondaryText;
    _desc.textColor = t.text;
    _descBack.image = TMRoundImage(t.elevated, 12);
    [self styleSubscribe];
}

- (void)styleSubscribe {
    if (!_subscribe) return;
    BOOL subscribed = [[TMLibrary shared] isSubscribed:_channel.channelID];
    _subscribe.pillStyle = subscribed ? TMPillStyleGray : TMPillStyleInverse;
    _subscribe.title = _busy ? @"…" : (subscribed ? @"Đã theo dõi" : @"Theo dõi");
}

- (void)fillHeader {
    _name.text = _channel.name;
    NSString *subs = _channel.subscribers > 0 ? [NSString stringWithFormat:@"%@ người đăng ký", [TMFormat count:_channel.subscribers]] : @"";
    NSString *vids = _channel.videoCount > 0 ? [NSString stringWithFormat:@"%@ video", [TMFormat count:_channel.videoCount]] : @"";
    _meta.text = [TMFormat join:@[ subs, vids ]];
    _desc.text = _channel.summary ?: @"";
    _desc.numberOfLines = _descExpanded ? 0 : 3;
    [self styleSubscribe];
    CGFloat a = [self avatarSize];
    NSString *url = _channel.avatarURL.length ? _channel.avatarURL : [[TMLibrary shared] avatarForChannel:_channel.channelID];
    [[TMImageLoader shared] setImageURL:url.length ? [NSURL URLWithString:url] : nil
                            onImageView:_avatar
                            placeholder:TMLetterAvatar(_channel.name ?: @"", a)
                                   size:CGSizeMake(a, a)
                                 radius:a / 2];
    [self layoutHeaderForce:YES];
}

- (CGFloat)avatarSize {
    return TMIsPhone() ? 72 : 88;
}

- (void)layoutHeaderForce:(BOOL)force {
    CGFloat W = self.tableView.bounds.size.width;
    if (!force && W == _laidOutWidth) return;
    _laidOutWidth = W;
    CGFloat m = TMListMargin(), inner = W - 2 * m, a = [self avatarSize];
    _avatar.frame = CGRectMake(m, 12, a, a);
    CGFloat x = m + a + 16, w = W - x - m;
    CGSize ns = [_name.text sizeWithFont:_name.font constrainedToSize:CGSizeMake(w, 64) lineBreakMode:TMLineBreakWord];
    CGSize ms = [_meta.text sizeWithFont:_meta.font constrainedToSize:CGSizeMake(w, 40) lineBreakMode:TMLineBreakWord];
    CGFloat block = ceil(ns.height) + (ms.height > 0 ? 4 + ceil(ms.height) : 0);
    CGFloat y = 12 + MAX(0, floor((a - block) / 2));
    _name.frame = CGRectMake(x, y, w, ceil(ns.height));
    _meta.frame = CGRectMake(x, CGRectGetMaxY(_name.frame) + 4, w, ceil(ms.height));
    y = MAX(CGRectGetMaxY(_avatar.frame), CGRectGetMaxY(_meta.frame)) + 16;
    _subscribe.frame = CGRectMake(m, y, MIN(inner, 420), 38);
    y += 38 + 14;
    if (_desc.text.length) {
        CGFloat maxH = _descExpanded ? 3000 : 3 * _desc.font.lineHeight + 2;
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
    // Search results carry most fields, a video page only the id and name: fetch the header once
    [[TMAPIClient shared] channel:_channel.channelID
                       completion:^(TMChannel *full, NSString *error) {
                           if (!full) return;
                           if (!full.name.length) full.name = self->_channel.name;
                           self->_channel = full;
                           [[TMLibrary shared] rememberChannel:full];
                           [self fillHeader];
                       }];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self layoutHeaderForce:NO];
}

#pragma mark - Actions

- (void)toggleSubscribe {
    if (_busy || !_channel.channelID.length) return;
    BOOL subscribe = ![[TMLibrary shared] isSubscribed:_channel.channelID];
    _busy = YES;
    [self styleSubscribe];
    [[TMLibrary shared] setSubscribed:subscribe
                            channelID:_channel.channelID
                           completion:^(NSString *error) {
                               self->_busy = NO;
                               [self styleSubscribe];
                               if (error) {
                                   [TMAlert showTitle:subscribe ? @"Không theo dõi được" : @"Không bỏ theo dõi được" message:error button:@"Đóng"];
                               }
                           }];
}

- (void)toggleDescription {
    _descExpanded = !_descExpanded;
    _desc.numberOfLines = _descExpanded ? 0 : 3;
    [self layoutHeaderForce:YES];
}

- (void)segmentChanged {
    [self showSection:_segment.selectedSegmentIndex];
}

@end
