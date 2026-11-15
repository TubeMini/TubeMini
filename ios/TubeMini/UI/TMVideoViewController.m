#import "TMVideoViewController.h"
#import "TMFormat.h"
#import "TMImageLoader.h"
#import "TMPlayer.h"
#import "TMTheme.h"

@implementation TMVideoViewController {
    TMVideo *_video;
    UIView *_header;
    UIImageView *_thumb;
    UIButton *_playOverlay, *_playButton, *_qualityButton, *_channelButton;
    UILabel *_title, *_meta, *_desc;
    UISegmentedControl *_segment;
    BOOL _descExpanded;
    NSInteger _quality;
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
    _channelButton = makeButton(@"Video của kênh", self, @selector(openChannel));
    [_header addSubview:_playButton];
    [_header addSubview:_qualityButton];
    [_header addSubview:_channelButton];

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
    for (UIButton *b in @[ _playButton ?: [NSNull null], _qualityButton ?: [NSNull null], _channelButton ?: [NSNull null] ]) {
        if ([b isKindOfClass:[UIButton class]]) [t styleButton:b];
    }
    _segment.tintColor = t.dark ? [UIColor colorWithWhite:0.28 alpha:1] : [UIColor colorWithRed:0.62 green:0.08 blue:0.08 alpha:1];
}

- (void)fillHeader {
    _title.text = _video.title;
    _meta.text = [TMFormat join:@[ _video.author ?: @"", [TMFormat views:_video.views], [TMFormat relativeDate:_video.published] ]];
    _desc.text = _video.descriptionText.length ? _video.descriptionText : @"";
    _desc.numberOfLines = _descExpanded ? 0 : 4;
    [_qualityButton setTitle:[NSString stringWithFormat:@"Chất lượng: %ldp", (long)_quality] forState:UIControlStateNormal];
    _channelButton.hidden = _video.authorID.length == 0;
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
    CGFloat bw = MIN(220, (inner - 20) / 3);
    _playButton.frame = CGRectMake(pad, y, bw, 40);
    _qualityButton.frame = CGRectMake(pad + bw + 10, y, bw, 40);
    _channelButton.frame = CGRectMake(pad + 2 * (bw + 10), y, bw, 40);
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
    // List entries (related videos) have no description: fetch the full entry once
    [[TMAPIClient shared] video:_video.videoID
                     completion:^(TMVideo *full, NSString *error) {
                         if (!full) return;
                         self->_video = full;
                         [self fillHeader];
                     }];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self layoutHeaderForce:NO];
}

#pragma mark - Actions

- (void)play {
    [[TMPlayer shared] playVideo:_video quality:_quality from:self];
}

- (void)chooseQuality {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chất lượng phát"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"360p (nhẹ, ổn định)", @"720p (HD)", nil];
    [sheet showFromRect:_qualityButton.frame inView:_header animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex < 0 || buttonIndex > 1) return;
    _quality = buttonIndex == 1 ? 720 : 360;
    [_qualityButton setTitle:[NSString stringWithFormat:@"Chất lượng: %ldp", (long)_quality] forState:UIControlStateNormal];
}

- (void)openChannel {
    NSString *cid = _video.authorID;
    TMListViewController *uploads =
        [[TMListViewController alloc] initWithTitle:_video.author
                                          firstPage:^(TMFeedBlock done) { [[TMAPIClient shared] uploads:cid completion:done]; }];
    uploads.emptyMessage = @"Kênh chưa có video.";
    [self.navigationController pushViewController:uploads animated:YES];
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
