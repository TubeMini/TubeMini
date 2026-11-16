#import "TMCells.h"
#import "TMFormat.h"
#import "TMImageLoader.h"
#import "TMTheme.h"

/// List thumbnail: 160×90 on the iPad, 128×72 on an iPhone (at 320 pt the title needs the room).
static CGSize TMThumbSize(void) {
    static CGSize size;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL phone = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone;
        size = phone ? CGSizeMake(128, 72) : CGSizeMake(160, 90);
    });
    return size;
}
#define kThumbW (TMThumbSize().width)
#define kThumbH (TMThumbSize().height)

/// Background + selection colours of a cell for the current theme.
static void themeCell(UITableViewCell *cell) {
    TMTheme *t = [TMTheme current];
    cell.backgroundColor = t.cellBackground;
    cell.contentView.backgroundColor = t.cellBackground;
    UIView *sel = cell.selectedBackgroundView;
    if (!sel || sel.tag != 77) {
        sel = [[UIView alloc] init];
        sel.tag = 77;
        cell.selectedBackgroundView = sel;
    }
    sel.backgroundColor = t.selection;
}

static UILabel *makeLabel(UIFont *font, UIColor *color, NSInteger lines) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.numberOfLines = lines;
    l.backgroundColor = [UIColor clearColor];
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    return l;
}

#pragma mark - Video

@implementation TMVideoCell {
    UIImageView *_thumb;
    UILabel *_duration, *_title, *_meta;
    UIView *_progress;
    CGFloat _fraction; // watched part of the video, 0 = no bar
}

+ (CGFloat)height {
    return kThumbH + 16;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _thumb = [[UIImageView alloc] initWithFrame:CGRectMake(10, 8, kThumbW, kThumbH)];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        [self.contentView addSubview:_thumb];
        _duration = makeLabel([UIFont boldSystemFontOfSize:12], [UIColor whiteColor], 1);
        _duration.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
        _duration.textAlignment = NSTextAlignmentCenter;
        [_thumb addSubview:_duration];
        _progress = [[UIView alloc] init];
        _progress.backgroundColor = [UIColor colorWithRed:0.9 green:0.1 blue:0.1 alpha:1];
        [_thumb addSubview:_progress];
        _title = makeLabel([UIFont boldSystemFontOfSize:16], [UIColor blackColor], 2);
        [self.contentView addSubview:_title];
        _meta = makeLabel([UIFont systemFontOfSize:13], [UIColor darkGrayColor], 2);
        [self.contentView addSubview:_meta];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 10 + kThumbW + 12, w = self.contentView.bounds.size.width - x - 10;
    CGSize t = [_title.text sizeWithFont:_title.font constrainedToSize:CGSizeMake(w, 40) lineBreakMode:NSLineBreakByTruncatingTail];
    _title.frame = CGRectMake(x, 10, w, t.height);
    CGSize m = [_meta.text sizeWithFont:_meta.font constrainedToSize:CGSizeMake(w, 34) lineBreakMode:NSLineBreakByTruncatingTail];
    _meta.frame = CGRectMake(x, 14 + t.height, w, m.height);
    CGSize d = [_duration.text sizeWithFont:_duration.font];
    _duration.hidden = _duration.text.length == 0;
    _duration.frame = CGRectMake(kThumbW - d.width - 10, kThumbH - 20, d.width + 8, 17);
    _progress.hidden = _fraction <= 0;
    _progress.frame = CGRectMake(0, kThumbH - 4, floor(kThumbW * _fraction), 4);
}

- (void)configureWithVideo:(TMVideo *)v {
    themeCell(self);
    _title.textColor = [TMTheme current].text;
    _meta.textColor = [TMTheme current].secondaryText;
    _title.text = v.title.length ? v.title : v.videoID;
    if (v.watched) {
        NSString *seen = v.position > 0 && v.duration > 0
                             ? [NSString stringWithFormat:@"Đã xem %@ / %@", [TMFormat duration:v.position], [TMFormat duration:v.duration]]
                             : @"Đã xem";
        _meta.text = [TMFormat join:@[ v.author ?: @"", seen, [TMFormat relativeDate:v.watched] ]];
    } else {
        _meta.text = [TMFormat join:@[ v.author ?: @"", [TMFormat views:v.views], [TMFormat relativeDate:v.published] ]];
    }
    _fraction = v.duration > 0 ? MIN(1, (CGFloat)v.position / v.duration) : 0;
    _duration.text = [TMFormat duration:v.duration];
    CGSize size = CGSizeMake(kThumbW, kThumbH);
    [[TMImageLoader shared] setImageURL:v.thumbnailURL
                            onImageView:_thumb
                            placeholder:[TMImageLoader placeholderOfSize:size]
                                   size:size];
    [self setNeedsLayout];
}

- (void)configureWithVideo:(TMVideo *)video meta:(NSString *)meta progress:(CGFloat)progress {
    [self configureWithVideo:video];
    _meta.text = meta;
    _fraction = progress;
    [self setNeedsLayout];
}

- (void)configureWithPlaylist:(TMPlaylist *)p {
    themeCell(self);
    _title.textColor = [TMTheme current].text;
    _meta.textColor = [TMTheme current].secondaryText;
    _title.text = p.title;
    _meta.text = [TMFormat join:@[ p.count > 0 ? [NSString stringWithFormat:@"%ld video", (long)p.count] : @"", p.author ?: @"" ]];
    _duration.text = @"";
    _fraction = 0;
    // The feed lists the 120×90 "default" first: the 320×180 one fits the cell better
    NSString *url = [p.thumbnailURL stringByReplacingOccurrencesOfString:@"/default.jpg" withString:@"/mqdefault.jpg"];
    CGSize size = CGSizeMake(kThumbW, kThumbH);
    [[TMImageLoader shared] setImageURL:[NSURL URLWithString:url]
                            onImageView:_thumb
                            placeholder:[TMImageLoader placeholderOfSize:size]
                                   size:size];
    [self setNeedsLayout];
}

@end

#pragma mark - Channel

@implementation TMChannelCell {
    UIImageView *_avatar;
    UILabel *_name, *_meta;
}

+ (CGFloat)height {
    return 80;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _avatar = [[UIImageView alloc] initWithFrame:CGRectMake(10, 8, 64, 64)];
        [self.contentView addSubview:_avatar];
        _name = makeLabel([UIFont boldSystemFontOfSize:17], [UIColor blackColor], 1);
        [self.contentView addSubview:_name];
        _meta = makeLabel([UIFont systemFontOfSize:13], [UIColor darkGrayColor], 2);
        [self.contentView addSubview:_meta];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 86, w = self.contentView.bounds.size.width - x - 10;
    _name.frame = CGRectMake(x, 16, w, 22);
    _meta.frame = CGRectMake(x, 40, w, 32);
}

- (void)configureWithChannel:(TMChannel *)c {
    themeCell(self);
    _name.textColor = [TMTheme current].text;
    _meta.textColor = [TMTheme current].secondaryText;
    _name.text = c.name;
    NSString *subs = c.subscribers > 0 ? [NSString stringWithFormat:@"%@ người đăng ký", [TMFormat count:c.subscribers]] : @"";
    NSString *vids = c.videoCount > 0 ? [NSString stringWithFormat:@"%@ video", [TMFormat count:c.videoCount]] : @"";
    _meta.text = [TMFormat join:@[ subs, vids ]];
    CGSize size = CGSizeMake(64, 64);
    [[TMImageLoader shared] setImageURL:[NSURL URLWithString:c.avatarURL]
                            onImageView:_avatar
                            placeholder:[TMImageLoader placeholderOfSize:size]
                                   size:size];
}

@end

#pragma mark - Comment

@implementation TMCommentCell {
    UILabel *_head, *_text;
}

+ (UIFont *)textFont {
    return [UIFont systemFontOfSize:15];
}

+ (CGFloat)heightForComment:(TMComment *)c width:(CGFloat)width {
    CGSize s = [c.text sizeWithFont:[self textFont]
                  constrainedToSize:CGSizeMake(width - 30, 400)
                      lineBreakMode:NSLineBreakByWordWrapping];
    return 36 + s.height + 10;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        _head = makeLabel([UIFont boldSystemFontOfSize:13], [UIColor darkGrayColor], 1);
        [self.contentView addSubview:_head];
        _text = makeLabel([TMCommentCell textFont], [UIColor blackColor], 0);
        _text.lineBreakMode = NSLineBreakByWordWrapping;
        [self.contentView addSubview:_text];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width - 30;
    _head.frame = CGRectMake(15, 10, w, 18);
    CGSize s = [_text.text sizeWithFont:_text.font constrainedToSize:CGSizeMake(w, 400) lineBreakMode:NSLineBreakByWordWrapping];
    _text.frame = CGRectMake(15, 34, w, s.height);
}

- (void)configureWithComment:(TMComment *)c {
    themeCell(self);
    _head.textColor = [TMTheme current].secondaryText;
    _text.textColor = [TMTheme current].text;
    NSString *replies = c.replies > 0 ? [NSString stringWithFormat:@"%ld trả lời", (long)c.replies] : @"";
    _head.text = [TMFormat join:@[ c.author ?: @"", [TMFormat relativeDate:c.published], replies ]];
    _text.text = c.text;
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
        _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spin.center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
        _spin.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [self addSubview:_spin];
        _label = makeLabel([UIFont systemFontOfSize:15], [UIColor grayColor], 3);
        _label.textAlignment = NSTextAlignmentCenter;
        _label.frame = CGRectInset(self.bounds, 20, 4);
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
    _spin.activityIndicatorViewStyle = t.dark ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;
}

@end
