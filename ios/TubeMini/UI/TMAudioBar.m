#import "TMAudioBar.h"
#import "TMAudioPlayer.h"
#import "TMFormat.h"
#import "TMImageLoader.h"

@implementation TMAudioBar {
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
    CGFloat want = [TMAudioPlayer shared].active ? [self height] : 0;
    if (sv.contentInset.bottom == want) return;
    UIEdgeInsets inset = sv.contentInset, indicator = sv.scrollIndicatorInsets;
    inset.bottom = want;
    indicator.bottom = want;
    sv.contentInset = inset;
    sv.scrollIndicatorInsets = indicator;
}

static UIButton *barButton(NSString *title, CGFloat size, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.4] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:size];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
        self.hidden = YES;
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 1)];
        line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
        line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self addSubview:line];

        _seek = [[UISlider alloc] init];
        _seek.minimumTrackTintColor = [UIColor colorWithRed:0.9 green:0.15 blue:0.12 alpha:1];
        _seek.maximumTrackTintColor = [UIColor colorWithWhite:0.35 alpha:1];
        [_seek addTarget:self action:@selector(seekMoved) forControlEvents:UIControlEventValueChanged];
        [_seek addTarget:self action:@selector(seekBegan) forControlEvents:UIControlEventTouchDown];
        [_seek addTarget:self action:@selector(seekEnded)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self addSubview:_seek];

        _thumb = [[UIImageView alloc] init];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.userInteractionEnabled = YES;
        [_thumb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)]];
        [self addSubview:_thumb];

        _title = [[UILabel alloc] init];
        _title.font = [UIFont boldSystemFontOfSize:15];
        _title.textColor = [UIColor whiteColor];
        _title.backgroundColor = [UIColor clearColor];
        _title.userInteractionEnabled = YES;
        [_title addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open)]];
        [self addSubview:_title];
        _time = [[UILabel alloc] init];
        _time.font = [UIFont systemFontOfSize:13];
        _time.textColor = [UIColor colorWithWhite:0.75 alpha:1];
        _time.backgroundColor = [UIColor clearColor];
        [self addSubview:_time];

        _back = barButton(@"↺15", 17, self, @selector(back));
        _play = barButton(@"❚❚", 22, self, @selector(toggle));
        _forward = barButton(@"15↻", 17, self, @selector(forward));
        _close = barButton(@"✕", 20, self, @selector(close));
        for (UIButton *b in @[ _back, _play, _forward, _close ]) [self addSubview:b];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(update)
                                                     name:TMAudioPlayerDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    _seek.frame = CGRectMake(10, 2, W - 20, 23);
    // An iPhone in portrait (320 pt) has no room for the thumbnail: the title gets it
    BOOL narrow = W < 400;
    _thumb.hidden = narrow;
    _thumb.frame = CGRectMake(10, 28, 64, 36);
    CGFloat bw = narrow ? 44 : 52, buttons = 4 * bw;
    CGFloat x = narrow ? 10 : 84, w = W - x - buttons - 10;
    _title.frame = CGRectMake(x, 28, w, 20);
    _time.frame = CGRectMake(x, 47, w, 17);
    CGFloat bx = W - buttons - 6;
    for (UIButton *b in @[ _back, _play, _forward, _close ]) {
        b.frame = CGRectMake(bx, 26, bw, 40);
        bx += bw;
    }
}

- (void)update {
    TMAudioPlayer *a = [TMAudioPlayer shared];
    if (!a.active) {
        self.hidden = YES;
        _shownVideo = nil;
        return;
    }
    self.hidden = NO;
    [self.superview bringSubviewToFront:self];
    if (![_shownVideo isEqualToString:a.video.videoID]) {
        _shownVideo = a.video.videoID;
        _title.text = [NSString stringWithFormat:@"♫ %@", a.video.title ?: @""];
        CGSize size = CGSizeMake(64, 36);
        [[TMImageLoader shared] setImageURL:a.video.thumbnailURL
                                onImageView:_thumb
                                placeholder:[TMImageLoader placeholderOfSize:size]
                                       size:size];
    }
    [_play setTitle:a.playing ? @"❚❚" : @"►" forState:UIControlStateNormal]; // "▶" turns into a blue emoji on iOS 6
    if (_dragging) return;
    NSTimeInterval d = a.duration;
    _seek.maximumValue = d > 0 ? d : 1;
    _seek.value = a.position;
    [self showTime:a.position duration:d];
}

- (void)showTime:(NSTimeInterval)t duration:(NSTimeInterval)d {
    NSString *pos = [TMFormat duration:(NSInteger)t];
    _time.text = d > 0 ? [NSString stringWithFormat:@"%@ / %@", pos.length ? pos : @"0:00", [TMFormat duration:(NSInteger)d]] : pos;
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
