#import "TMCells.h"
#import "TMCompat.h"
#import "TMFormat.h"
#import "TMGlass.h"
#import "TMIcons.h"
#import "TMImageLoader.h"
#import "TMLibrary.h"
#import "TMTheme.h"
#import <QuartzCore/QuartzCore.h>

CGFloat TMListMargin(void) {
    return TMIsPhone() ? 12 : 20;
}

UIImage *TMLetterAvatar(NSString *name, CGFloat size) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    NSString *letter = @"?";
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed hasPrefix:@"@"]) trimmed = [trimmed substringFromIndex:1];
    if (trimmed.length) letter = [[trimmed substringWithRange:[trimmed rangeOfComposedCharacterSequenceAtIndex:0]] uppercaseString];
    NSUInteger hash = 0;
    for (NSUInteger i = 0; i < name.length; i++) hash = hash * 31 + [name characterAtIndex:i];
    static const int palette[][3] = {{229, 57, 53},  {216, 27, 96},  {142, 36, 170}, {94, 53, 177}, {57, 73, 171},  {30, 136, 229},
                                     {3, 155, 229},  {0, 151, 167},  {0, 137, 123},  {67, 160, 71}, {124, 159, 56}, {240, 160, 0},
                                     {245, 124, 0},  {244, 81, 30},  {121, 85, 72},  {84, 110, 122}};
    const int *rgb = palette[hash % 16];
    NSString *key = [NSString stringWithFormat:@"%@|%lu|%.0f", letter, (unsigned long)(hash % 16), size];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [[UIColor colorWithRed:rgb[0] / 255.0 green:rgb[1] / 255.0 blue:rgb[2] / 255.0 alpha:1] setFill];
    CGContextFillEllipseInRect(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, size, size));
    [[UIColor whiteColor] set];
    UIFont *font = TMFontMedium(round(size * 0.46));
    CGSize s = [letter sizeWithFont:font];
    [letter drawAtPoint:CGPointMake((size - s.width) / 2, (size - s.height) / 2) withFont:font];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [cache setObject:img forKey:key];
    return img;
}

/// Avatar of a channel: the real picture when TubeMini has seen it, else the letter.
static void setAvatar(UIImageView *view, NSString *channelID, NSString *name, CGFloat size) {
    NSString *url = [[TMLibrary shared] avatarForChannel:channelID];
    if (url.length) {
        [[TMImageLoader shared] setImageURL:[NSURL URLWithString:url]
                                onImageView:view
                                placeholder:TMLetterAvatar(name, size)
                                       size:CGSizeMake(size, size)
                                     radius:size / 2];
    } else {
        [[TMImageLoader shared] setImageURL:nil onImageView:view placeholder:TMLetterAvatar(name, size) size:CGSizeMake(size, size)];
    }
}

/// Rounded highlight behind a touched row, inset from the edges.
static void themeCell(UITableViewCell *cell) {
    TMTheme *t = [TMTheme current];
    cell.backgroundColor = t.background;
    cell.contentView.backgroundColor = [UIColor clearColor];
    UIView *sel = cell.selectedBackgroundView;
    if (!sel || sel.tag != 77) {
        sel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
        sel.tag = 77;
        sel.backgroundColor = [UIColor clearColor];
        UIImageView *pill = [[UIImageView alloc] initWithFrame:CGRectInset(sel.bounds, 6, 2)];
        pill.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [sel addSubview:pill];
        cell.selectedBackgroundView = sel;
    }
    ((UIImageView *)sel.subviews[0]).image = TMRoundImage(t.selection, 12);
}

static UILabel *makeLabel(UIFont *font, NSInteger lines) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.numberOfLines = lines;
    l.backgroundColor = [UIColor clearColor];
    l.lineBreakMode = TMLineBreakTail;
    return l;
}

/// Duration / count badge: white text on a dark rounded tag (bottom right of a thumbnail).
@interface TMBadge : UIView
@property (nonatomic, readonly) UILabel *label;
/// `lift`: room under it (the progress capsule).
- (void)placeInside:(CGSize)thumb lift:(CGFloat)lift;
@end

@implementation TMBadge
- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
        self.layer.cornerRadius = 4;
        _label = makeLabel(TMFontMedium(11.5), 1);
        _label.textColor = [UIColor whiteColor];
        _label.textAlignment = TMAlignCenter;
        [self addSubview:_label];
    }
    return self;
}

- (void)placeInside:(CGSize)thumb lift:(CGFloat)lift {
    self.hidden = _label.text.length == 0;
    CGSize s = [_label.text sizeWithFont:_label.font];
    CGFloat w = ceil(s.width) + 8, h = 17;
    self.frame = CGRectMake(thumb.width - w - 6, thumb.height - h - 6 - lift, w, h);
    _label.frame = self.bounds;
}
@end

/// Watched / downloaded part: a small capsule inside the bottom of the thumbnail.
@interface TMThumbProgress : UIView
@property (nonatomic) CGFloat fraction;
- (void)placeInside:(CGSize)thumb;
@end

@implementation TMThumbProgress {
    UIView *_fill;
}
- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.5];
        self.layer.cornerRadius = 1.5;
        _fill = [[UIView alloc] init];
        _fill.layer.cornerRadius = 1.5;
        [self addSubview:_fill];
    }
    return self;
}

- (void)placeInside:(CGSize)thumb {
    self.hidden = _fraction <= 0;
    self.frame = CGRectMake(8, thumb.height - 10, thumb.width - 16, 3);
    _fill.backgroundColor = [TMTheme current].brand;
    _fill.frame = CGRectMake(0, 0, MAX(3, floor(self.bounds.size.width * MIN(1, _fraction))), 3);
}
@end

#pragma mark - Video row

/// List thumbnail: 176×99 on the iPad, 144×81 on an iPhone (at 320 pt the title needs the room).
static CGSize TMThumbSize(void) {
    return TMIsPhone() ? CGSizeMake(144, 81) : CGSizeMake(176, 99);
}

static CGFloat TMThumbRadius(void) {
    return TMIsPhone() ? 8 : 10;
}

@implementation TMVideoCell {
    UIImageView *_thumb;
    TMBadge *_badge;
    TMThumbProgress *_progress;
    UILabel *_title, *_meta;
}

+ (CGFloat)height {
    return TMThumbSize().height + 16;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        CGSize ts = TMThumbSize();
        _thumb = [[UIImageView alloc] initWithFrame:CGRectMake(TMListMargin(), 8, ts.width, ts.height)];
        [self.contentView addSubview:_thumb];
        _badge = [[TMBadge alloc] init];
        [_thumb addSubview:_badge];
        _progress = [[TMThumbProgress alloc] init];
        [_thumb addSubview:_progress];
        _title = makeLabel(TMFontMedium(TMIsPhone() ? 14.5 : 15.5), 2);
        [self.contentView addSubview:_title];
        _meta = makeLabel(TMFontRegular(12.5), 2);
        [self.contentView addSubview:_meta];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize ts = TMThumbSize();
    CGFloat x = TMListMargin() + ts.width + 12, w = self.contentView.bounds.size.width - x - TMListMargin();
    CGSize t = [_title.text sizeWithFont:_title.font constrainedToSize:CGSizeMake(w, _title.font.lineHeight * 2 + 1)
                           lineBreakMode:TMLineBreakTail];
    _title.frame = CGRectMake(x, 9, w, ceil(t.height));
    CGSize m = [_meta.text sizeWithFont:_meta.font constrainedToSize:CGSizeMake(w, _meta.font.lineHeight * 2 + 1)
                          lineBreakMode:TMLineBreakTail];
    _meta.frame = CGRectMake(x, CGRectGetMaxY(_title.frame) + 3, w, ceil(m.height));
    [_badge placeInside:ts lift:_progress.fraction > 0 ? 9 : 0];
    [_progress placeInside:ts];
}

- (void)applyColours {
    themeCell(self);
    _title.textColor = [TMTheme current].text;
    _meta.textColor = [TMTheme current].secondaryText;
}

- (void)loadThumb:(NSURL *)url {
    [[TMImageLoader shared] setImageURL:url onImageView:_thumb size:TMThumbSize() radius:TMThumbRadius()];
}

- (void)configureWithVideo:(TMVideo *)v {
    [self applyColours];
    _title.text = v.title.length ? v.title : v.videoID;
    if (v.watched) {
        NSString *seen = v.position > 0 && v.duration > 0
                             ? [NSString stringWithFormat:@"Đã xem %@ / %@", [TMFormat duration:v.position], [TMFormat duration:v.duration]]
                             : @"Đã xem";
        _meta.text = [TMFormat join:@[ v.author ?: @"", seen, [TMFormat relativeDate:v.watched] ]];
    } else {
        _meta.text = [TMFormat join:@[ v.author ?: @"", [TMFormat views:v.views], [TMFormat relativeDate:v.published] ]];
    }
    _progress.fraction = v.duration > 0 ? MIN(1, (CGFloat)v.position / v.duration) : 0;
    _badge.label.text = [TMFormat duration:v.duration];
    [self loadThumb:v.thumbnailURL];
    [self setNeedsLayout];
}

- (void)configureWithVideo:(TMVideo *)video meta:(NSString *)meta progress:(CGFloat)progress {
    [self configureWithVideo:video];
    _meta.text = meta;
    _progress.fraction = progress;
    [self setNeedsLayout];
}

- (void)configureWithPlaylist:(TMPlaylist *)p {
    [self applyColours];
    _title.text = p.title;
    _meta.text = p.author ?: @"";
    _badge.label.text = p.count > 0 ? [NSString stringWithFormat:@"%ld video", (long)p.count] : @"Playlist";
    _progress.fraction = 0;
    // The feed lists the 120×90 "default" first: the 320×180 one fits the cell better
    NSString *url = [p.thumbnailURL stringByReplacingOccurrencesOfString:@"/default.jpg" withString:@"/mqdefault.jpg"];
    [self loadThumb:[NSURL URLWithString:url]];
    [self setNeedsLayout];
}

@end

#pragma mark - Video cards

/// One card: thumbnail, avatar, title, meta. Fades while touched.
@interface TMCardTile : UIControl
@property (nonatomic, readonly) UIImageView *thumb, *avatar;
@property (nonatomic, readonly) TMBadge *badge;
@property (nonatomic, readonly) TMThumbProgress *progress;
@property (nonatomic, readonly) UILabel *title, *meta;
@end

@implementation TMCardTile
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _thumb = [[UIImageView alloc] init];
        [self addSubview:_thumb];
        _badge = [[TMBadge alloc] init];
        [_thumb addSubview:_badge];
        _progress = [[TMThumbProgress alloc] init];
        [_thumb addSubview:_progress];
        _avatar = [[UIImageView alloc] init];
        [self addSubview:_avatar];
        _title = makeLabel(TMFontMedium(TMIsPhone() ? 15 : 15.5), 2);
        [self addSubview:_title];
        _meta = makeLabel(TMFontRegular(12.5), 2);
        [self addSubview:_meta];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1;
}
@end

static const CGFloat kAvatar = 36;

@implementation TMVideoCardRow {
    NSMutableArray *_tiles;
    NSArray *_videos;
    NSInteger _first;
}

+ (NSInteger)columnsForWidth:(CGFloat)W {
    return W < 500 ? 1 : (W < 900 ? 2 : 3);
}

+ (CGFloat)gap {
    return TMIsPhone() ? 12 : 16;
}

+ (CGFloat)tileWidthFor:(CGFloat)W {
    NSInteger cols = [self columnsForWidth:W];
    return floor((W - 2 * TMListMargin() - (cols - 1) * [self gap]) / cols);
}

+ (UIFont *)titleFont {
    return TMFontMedium(TMIsPhone() ? 15 : 15.5);
}

/// One card column → "channel · views · age" on one line; narrower cards put the channel on its own line.
+ (NSInteger)metaLines:(CGFloat)W {
    return [self columnsForWidth:W] == 1 ? 1 : 2;
}

+ (CGFloat)heightForWidth:(CGFloat)W {
    CGFloat tw = [self tileWidthFor:W], th = round(tw * 9 / 16);
    CGFloat text = ceil([self titleFont].lineHeight * 2) + 3 + ceil(TMFontRegular(12.5).lineHeight * [self metaLines:W]);
    return th + 10 + MAX(text, kAvatar) + (TMIsPhone() ? 16 : 24);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _tiles = [NSMutableArray array];
    }
    return self;
}

- (void)configureWithVideos:(NSArray *)videos first:(NSInteger)first width:(CGFloat)W {
    TMTheme *t = [TMTheme current];
    self.backgroundColor = t.background;
    self.contentView.backgroundColor = t.background;
    _videos = videos;
    _first = first;
    NSInteger cols = [TMVideoCardRow columnsForWidth:W];
    while ((NSInteger)_tiles.count < cols) {
        TMCardTile *tile = [[TMCardTile alloc] initWithFrame:CGRectZero];
        [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:tile];
        [_tiles addObject:tile];
    }
    CGFloat tw = [TMVideoCardRow tileWidthFor:W];
    CGSize thumb = CGSizeMake(tw, round(tw * 9 / 16));
    NSInteger metaLines = [TMVideoCardRow metaLines:W];
    for (NSUInteger i = 0; i < _tiles.count; i++) {
        TMCardTile *tile = _tiles[i];
        tile.hidden = i >= videos.count || (NSInteger)i >= cols;
        tile.tag = (NSInteger)i;
        if (tile.hidden) continue;
        TMVideo *v = videos[i];
        tile.title.textColor = t.text;
        tile.meta.textColor = t.secondaryText;
        tile.title.text = v.title.length ? v.title : v.videoID;
        NSString *stats = [TMFormat join:@[ [TMFormat views:v.views], [TMFormat relativeDate:v.published] ]];
        if (v.watched) stats = [TMFormat join:@[ @"Đã xem", [TMFormat relativeDate:v.watched] ]];
        tile.meta.numberOfLines = metaLines;
        tile.meta.text = metaLines == 1 ? [TMFormat join:@[ v.author ?: @"", stats ]]
                                        : [NSString stringWithFormat:@"%@\n%@", v.author ?: @"", stats];
        tile.badge.label.text = [TMFormat duration:v.duration];
        tile.progress.fraction = v.duration > 0 ? MIN(1, (CGFloat)v.position / v.duration) : 0;
        NSURL *hq = [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/hqdefault.jpg", v.videoID]];
        [[TMImageLoader shared] setImageURL:hq onImageView:tile.thumb size:thumb radius:TMIsPhone() ? 12 : 14];
        setAvatar(tile.avatar, v.authorID, v.author ?: @"", kAvatar);
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.contentView.bounds.size.width, tw = [TMVideoCardRow tileWidthFor:W], gap = [TMVideoCardRow gap];
    CGFloat th = round(tw * 9 / 16), H = self.contentView.bounds.size.height;
    for (NSUInteger i = 0; i < _tiles.count; i++) {
        TMCardTile *tile = _tiles[i];
        tile.frame = CGRectMake(TMListMargin() + i * (tw + gap), 0, tw, H - 8);
        tile.thumb.frame = CGRectMake(0, 0, tw, th);
        [tile.badge placeInside:tile.thumb.bounds.size lift:tile.progress.fraction > 0 ? 9 : 0];
        [tile.progress placeInside:tile.thumb.bounds.size];
        tile.avatar.frame = CGRectMake(0, th + 10, kAvatar, kAvatar);
        CGFloat x = kAvatar + 10, w = tw - x;
        CGSize ts = [tile.title.text sizeWithFont:tile.title.font constrainedToSize:CGSizeMake(w, tile.title.font.lineHeight * 2 + 1)
                                    lineBreakMode:TMLineBreakTail];
        tile.title.frame = CGRectMake(x, th + 9, w, ceil(ts.height));
        CGFloat mh = ceil(tile.meta.font.lineHeight * tile.meta.numberOfLines);
        tile.meta.frame = CGRectMake(x, CGRectGetMaxY(tile.title.frame) + 3, w, mh);
    }
}

- (void)tileTapped:(TMCardTile *)tile {
    if (self.onTap) self.onTap(_first + tile.tag);
}

@end

#pragma mark - Channel

@implementation TMChannelCell {
    UIImageView *_avatar, *_chevron;
    UILabel *_name, *_meta;
}

+ (CGFloat)height {
    return 76;
}

+ (CGFloat)avatarSize {
    return TMIsPhone() ? 52 : 56;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _avatar = [[UIImageView alloc] init];
        [self.contentView addSubview:_avatar];
        _name = makeLabel(TMFontMedium(16), 1);
        [self.contentView addSubview:_name];
        _meta = makeLabel(TMFontRegular(13), 2);
        [self.contentView addSubview:_meta];
        _chevron = [[UIImageView alloc] init];
        _chevron.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_chevron];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat a = [TMChannelCell avatarSize], m = TMListMargin(), W = self.contentView.bounds.size.width;
    CGFloat H = self.contentView.bounds.size.height;
    _avatar.frame = CGRectMake(m, floor((H - a) / 2), a, a);
    _chevron.frame = CGRectMake(W - m - 16, floor((H - 16) / 2), 16, 16);
    CGFloat x = m + a + 14, w = CGRectGetMinX(_chevron.frame) - 8 - x;
    CGSize ms = [_meta.text sizeWithFont:_meta.font constrainedToSize:CGSizeMake(w, 34) lineBreakMode:TMLineBreakTail];
    CGFloat block = 20 + 2 + (ms.height > 0 ? ceil(ms.height) : 0), y = floor((H - block) / 2);
    _name.frame = CGRectMake(x, y, w, 20);
    _meta.frame = CGRectMake(x, y + 22, w, ceil(ms.height));
}

- (void)configureWithChannel:(TMChannel *)c {
    themeCell(self);
    TMTheme *t = [TMTheme current];
    _name.textColor = t.text;
    _meta.textColor = t.secondaryText;
    _chevron.image = TMIcon(@"chevron.right", 14, t.tertiaryText);
    _name.text = c.name;
    NSString *subs = c.subscribers > 0 ? [NSString stringWithFormat:@"%@ người đăng ký", [TMFormat count:c.subscribers]] : @"";
    NSString *vids = c.videoCount > 0 ? [NSString stringWithFormat:@"%@ video", [TMFormat count:c.videoCount]] : @"";
    _meta.text = [TMFormat join:@[ subs, vids ]];
    CGFloat a = [TMChannelCell avatarSize];
    [[TMLibrary shared] rememberChannel:c];
    if (c.avatarURL.length) {
        [[TMImageLoader shared] setImageURL:[NSURL URLWithString:c.avatarURL]
                                onImageView:_avatar
                                placeholder:TMLetterAvatar(c.name, a)
                                       size:CGSizeMake(a, a)
                                     radius:a / 2];
    } else {
        [[TMImageLoader shared] setImageURL:nil onImageView:_avatar placeholder:TMLetterAvatar(c.name, a) size:CGSizeMake(a, a)];
    }
    [self setNeedsLayout];
}

@end

#pragma mark - Comment

@implementation TMCommentCell {
    UIImageView *_avatar;
    UILabel *_head, *_text;
}

static const CGFloat kCommentAvatar = 32;

+ (UIFont *)textFont {
    return TMFontRegular(14.5);
}

+ (CGFloat)textWidth:(CGFloat)width {
    return width - 2 * TMListMargin() - kCommentAvatar - 10;
}

+ (CGFloat)heightForComment:(TMComment *)c width:(CGFloat)width {
    CGSize s = [c.text sizeWithFont:[self textFont]
                  constrainedToSize:CGSizeMake([self textWidth:width], 600)
                      lineBreakMode:TMLineBreakWord];
    return 12 + 18 + 3 + ceil(s.height) + 14;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _avatar = [[UIImageView alloc] init];
        [self.contentView addSubview:_avatar];
        _head = makeLabel(TMFontMedium(12.5), 1);
        [self.contentView addSubview:_head];
        _text = makeLabel([TMCommentCell textFont], 0);
        _text.lineBreakMode = TMLineBreakWord;
        [self.contentView addSubview:_text];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat m = TMListMargin(), x = m + kCommentAvatar + 10, w = [TMCommentCell textWidth:self.contentView.bounds.size.width];
    _avatar.frame = CGRectMake(m, 12, kCommentAvatar, kCommentAvatar);
    _head.frame = CGRectMake(x, 12, w, 18);
    CGSize s = [_text.text sizeWithFont:_text.font constrainedToSize:CGSizeMake(w, 600) lineBreakMode:TMLineBreakWord];
    _text.frame = CGRectMake(x, 33, w, ceil(s.height));
}

- (void)configureWithComment:(TMComment *)c {
    themeCell(self);
    _head.textColor = [TMTheme current].secondaryText;
    _text.textColor = [TMTheme current].text;
    NSString *replies = c.replies > 0 ? [NSString stringWithFormat:@"%ld trả lời", (long)c.replies] : @"";
    _head.text = [TMFormat join:@[ c.author ?: @"", [TMFormat relativeDate:c.published], replies ]];
    _text.text = c.text;
    _avatar.image = TMLetterAvatar(c.author ?: @"", kCommentAvatar);
    [self setNeedsLayout];
}

@end

#pragma mark - Footer

@implementation TMListFooter {
    UIActivityIndicatorView *_spin;
    UILabel *_label;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.backgroundColor = [UIColor clearColor];
        _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spin.center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
        _spin.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [self addSubview:_spin];
        _label = makeLabel(TMFontRegular(15), 4);
        _label.textAlignment = TMAlignCenter;
        _label.frame = CGRectInset(self.bounds, 28, 4);
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_label];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    }
    return self;
}

- (void)tapped {
    if (self.onTap && !_spin.isAnimating) self.onTap();
}

- (void)showLoading {
    _label.text = nil;
    [self applyTheme];
    [_spin startAnimating];
}

- (void)showMessage:(NSString *)message {
    [_spin stopAnimating];
    _label.text = message;
    [self applyTheme];
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    _label.textColor = t.secondaryText;
    _spin.activityIndicatorViewStyle = t.spinnerStyle;
}

@end
