#import "TMAudioBar.h"
#import "TMAudioPlayer.h"
#import "TMCompat.h"
#import "TMFormat.h"
#import "TMGlass.h"
#import "TMIcons.h"
#import "TMImageLoader.h"
#import "TMTabBarController.h"
#import "TMTheme.h"

@implementation TMAudioBar {
    TMGlassView *_glass;
    UISlider *_seek;
    UIImageView *_thumb;
    UILabel *_title, *_time;
    UIButton *_back, *_play, *_forward, *_close;
    BOOL _dragging;
    NSString *_shownVideo;
}

+ (CGFloat)height {
    return 70;
}

+ (void)applyInsetTo:(UIScrollView *)sv {
    CGFloat want = [TMTabBarController chromeHeight] + 12;
    if ([TMAudioPlayer shared].active) want += [self height] + 8;
    if (sv.contentInset.bottom == want) return;
    UIEdgeInsets inset = sv.contentInset, indicator = sv.scrollIndicatorInsets;
    inset.bottom = want;
    indicator.bottom = want;
    sv.contentInset = inset;
    sv.scrollIndicatorInsets = indicator;
}

- (UIButton *)button:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.showsTouchWhenHighlighted = NO;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, [TMAudioBar height])])) {
        self.backgroundColor = [UIColor clearColor];
        self.hidden = YES;
        _glass = [[TMGlassView alloc] initWithStyle:TMGlassStyleBar radius:24];
        _glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _glass.frame = self.bounds;
        [self addSubview:_glass];

        _seek = [[UISlider alloc] init];
        [_seek addTarget:self action:@selector(seekMoved) forControlEvents:UIControlEventValueChanged];
        [_seek addTarget:self action:@selector(seekBegan) forControlEvents:UIControlEventTouchDown];
        [_seek addTarget:self action:@selector(seekEnded)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self addSubview:_seek];

        _thumb = [[UIImageView alloc] init];
        _thumb.userInteractionEnabled = YES;
        [_thumb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)]];
        [self addSubview:_thumb];

        _title = [[UILabel alloc] init];
        _title.font = TMFontMedium(14);
        _title.backgroundColor = [UIColor clearColor];
        _title.userInteractionEnabled = YES;
        [_title addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)]];
        [self addSubview:_title];
        _time = [[UILabel alloc] init];
        _time.font = TMFontRegular(12);
        _time.backgroundColor = [UIColor clearColor];
        [self addSubview:_time];

        _back = [self button:@selector(back)];
        _play = [self button:@selector(toggle)];
        _forward = [self button:@selector(forward)];
        _close = [self button:@selector(close)];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(update)
                                                     name:TMAudioPlayerDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyTheme)
                                                     name:TMThemeDidChangeNotification
                                                   object:nil];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    _title.textColor = t.text;
    _time.textColor = t.secondaryText;
    [_back setImage:TMIcon(@"back15", 24, t.text) forState:UIControlStateNormal];
    [_forward setImage:TMIcon(@"fwd15", 24, t.text) forState:UIControlStateNormal];
    [_close setImage:TMIcon(@"close", 18, t.secondaryText) forState:UIControlStateNormal];
    TMStyleSlider(_seek, t.brand);
    [self updatePlayIcon];
}

- (void)updatePlayIcon {
    [_play setImage:TMIcon([TMAudioPlayer shared].playing ? @"pause" : @"play", 24, [TMTheme current].text) forState:UIControlStateNormal];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    // An iPhone in portrait has no room for the thumbnail: the title gets it
    BOOL narrow = W < 400;
    _thumb.hidden = narrow;
    _thumb.frame = CGRectMake(12, 10, 64, 36);
    CGFloat bw = narrow ? 38 : 44, buttons = 4 * bw;
    CGFloat x = narrow ? 18 : 88, w = W - x - buttons - 12;
    _title.frame = CGRectMake(x, 10, w, 18);
    _time.frame = CGRectMake(x, 29, w, 16);
    CGFloat bx = W - buttons - 8;
    for (UIButton *b in @[ _back, _play, _forward, _close ]) {
        b.frame = CGRectMake(bx, 6, bw, 44);
        bx += bw;
    }
    _seek.frame = CGRectMake(16, 46, W - 32, 20);
}

- (void)update {
    TMAudioPlayer *a = [TMAudioPlayer shared];
    if (!a.active) {
        self.hidden = YES;
        _shownVideo = nil;
        return;
    }
    self.hidden = NO;
    if (![_shownVideo isEqualToString:a.video.videoID]) {
        _shownVideo = a.video.videoID;
        _title.text = a.video.title ?: @"";
        [[TMImageLoader shared] setImageURL:a.video.thumbnailURL onImageView:_thumb size:CGSizeMake(64, 36) radius:7];
    }
    [self updatePlayIcon];
    if (_dragging) return;
    NSTimeInterval d = a.duration;
    _seek.maximumValue = d > 0 ? d : 1;
    _seek.value = a.position;
    [self showTime:a.position duration:d];
}

- (void)showTime:(NSTimeInterval)t duration:(NSTimeInterval)d {
    NSString *pos = [TMFormat duration:(NSInteger)t];
    NSString *time = d > 0 ? [NSString stringWithFormat:@"%@ / %@", pos.length ? pos : @"0:00", [TMFormat duration:(NSInteger)d]] : pos;
    if (!time.length) time = @"…";
    _time.text = self.bounds.size.width < 400 ? time : [NSString stringWithFormat:@"Chỉ nghe · %@", time]; // narrow: the time only
}

#pragma mark - Actions

- (void)seekBegan {
    _dragging = YES;
}

- (void)seekMoved {
    [self showTime:_seek.value duration:_seek.maximumValue]; // preview while dragging
}

- (void)seekEnded {
    _dragging = NO;
    [[TMAudioPlayer shared] seekTo:_seek.value];
}

- (void)back {
    [[TMAudioPlayer shared] skip:-15];
}

- (void)forward {
    [[TMAudioPlayer shared] skip:15];
}

- (void)toggle {
    [[TMAudioPlayer shared] togglePlay];
}

- (void)close {
    [[TMAudioPlayer shared] stop];
}

- (void)open {
    if (self.onOpen) self.onOpen();
}

@end
