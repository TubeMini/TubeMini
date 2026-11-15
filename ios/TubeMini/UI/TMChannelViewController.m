#import "TMChannelViewController.h"
#import "TMFormat.h"
#import "TMImageLoader.h"
#import "TMLibrary.h"
#import "TMTheme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kAvatar = 88;

@implementation TMChannelViewController {
    TMChannel *_channel;
    UIView *_header;
    UIImageView *_avatar;
    UILabel *_name, *_meta, *_desc;
    UIButton *_subscribe;
    UISegmentedControl *_segment;
    BOOL _descExpanded, _busy;
    CGFloat _laidOutWidth;
}

- (instancetype)initWithChannel:(TMChannel *)channel {
    if ((self = [super initWithTitle:channel.name firstPage:nil])) {
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
    return l;
}

- (void)buildHeader {
    _header = [[UIView alloc] initWithFrame:CGRectZero];
    _avatar = [[UIImageView alloc] init];
    _avatar.layer.cornerRadius = kAvatar / 2;
    _avatar.clipsToBounds = YES;
    [_header addSubview:_avatar];
    _name = headerLabel([UIFont boldSystemFontOfSize:22], 2);
    [_header addSubview:_name];
    _meta = headerLabel([UIFont systemFontOfSize:15], 1);
    [_header addSubview:_meta];
    _subscribe = [UIButton buttonWithType:UIButtonTypeCustom];
    _subscribe.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_subscribe addTarget:self action:@selector(toggleSubscribe) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_subscribe];
    _desc = headerLabel([UIFont systemFontOfSize:14], 3);
    _desc.userInteractionEnabled = YES;
    [_desc addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDescription)]];
    [_header addSubview:_desc];
    _segment = [[UISegmentedControl alloc] initWithItems:@[ @"Video", @"Playlist" ]];
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
    _name.textColor = t.text;
    _meta.textColor = t.secondaryText;
    _desc.textColor = t.secondaryText;
    _segment.tintColor = t.dark ? [UIColor colorWithWhite:0.28 alpha:1] : [UIColor colorWithRed:0.62 green:0.08 blue:0.08 alpha:1];
    [self styleSubscribe];
}

- (void)styleSubscribe {
    if (!_subscribe) return;
    [[TMTheme current] styleSubscribeButton:_subscribe subscribed:[[TMLibrary shared] isSubscribed:_channel.channelID] busy:_busy];
}

- (void)fillHeader {
    _name.text = _channel.name;
    NSString *subs = _channel.subscribers > 0 ? [NSString stringWithFormat:@"%@ người đăng ký", [TMFormat count:_channel.subscribers]] : @"";
    NSString *vids = _channel.videoCount > 0 ? [NSString stringWithFormat:@"%@ video", [TMFormat count:_channel.videoCount]] : @"";
    _meta.text = [TMFormat join:@[ subs, vids ]];
    _desc.text = _channel.summary ?: @"";
    _desc.numberOfLines = _descExpanded ? 0 : 3;
    [self styleSubscribe];
    if (_channel.avatarURL.length) {
        CGSize size = CGSizeMake(kAvatar, kAvatar);
        [[TMImageLoader shared] setImageURL:[NSURL URLWithString:_channel.avatarURL]
                                onImageView:_avatar
                                placeholder:[TMImageLoader placeholderOfSize:size]
                                       size:size];
    } else {
        _avatar.image = [TMImageLoader placeholderOfSize:CGSizeMake(kAvatar, kAvatar)];
    }
    [self layoutHeaderForce:YES];
}

- (void)layoutHeaderForce:(BOOL)force {
    CGFloat W = self.tableView.bounds.size.width;
    if (!force && W == _laidOutWidth) return;
    _laidOutWidth = W;
    CGFloat pad = 15, inner = W - 2 * pad;
    _avatar.frame = CGRectMake(pad, 14, kAvatar, kAvatar);
    CGFloat x = pad + kAvatar + 16, w = W - x - pad;
    CGSize ns = [_name.text sizeWithFont:_name.font constrainedToSize:CGSizeMake(w, 60) lineBreakMode:NSLineBreakByWordWrapping];
    _name.frame = CGRectMake(x, 16, w, ns.height);
    CGFloat y = CGRectGetMaxY(_name.frame) + 2;
    _meta.frame = CGRectMake(x, y, w, _meta.text.length ? 20 : 0);
    y = CGRectGetMaxY(_meta.frame) + 8;
    _subscribe.frame = CGRectMake(x, y, MIN(190, w), 38);
    y = MAX(CGRectGetMaxY(_avatar.frame), CGRectGetMaxY(_subscribe.frame)) + 12;
    if (_desc.text.length) {
        CGFloat maxH = _descExpanded ? 2000 : 3 * _desc.font.lineHeight + 2;
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
    // Search results carry most fields, a video page only the id and name: fetch the header once
    [[TMAPIClient shared] channel:_channel.channelID
                       completion:^(TMChannel *full, NSString *error) {
                           if (!full) return;
                           if (!full.name.length) full.name = self->_channel.name;
                           self->_channel = full;
                           self.title = full.name;
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
    _desc.numberOfLines = _descExpanded ? 0 : 3;
    [self layoutHeaderForce:YES];
}

- (void)segmentChanged {
    [self showSection:_segment.selectedSegmentIndex];
}

@end
