#import "TMGlass.h"
#import "TMCompat.h"
#import "TMIcons.h"
#import "TMTheme.h"
#import <QuartzCore/QuartzCore.h>

static CGPathRef roundedPath(CGRect r, CGFloat radius) {
    CGMutablePathRef p = CGPathCreateMutable();
    radius = MIN(radius, MIN(r.size.width, r.size.height) / 2);
    CGFloat x0 = CGRectGetMinX(r), x1 = CGRectGetMaxX(r), y0 = CGRectGetMinY(r), y1 = CGRectGetMaxY(r);
    CGPathMoveToPoint(p, NULL, x0 + radius, y0);
    CGPathAddArcToPoint(p, NULL, x1, y0, x1, y1, radius);
    CGPathAddArcToPoint(p, NULL, x1, y1, x0, y1, radius);
    CGPathAddArcToPoint(p, NULL, x0, y1, x0, y0, radius);
    CGPathAddArcToPoint(p, NULL, x0, y0, x1, y0, radius);
    CGPathCloseSubpath(p);
    return p;
}

static void verticalGradient(CGContextRef c, CGFloat y0, CGFloat y1, UIColor *top, UIColor *bottom) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (__bridge id)top.CGColor, (__bridge id)bottom.CGColor ];
    CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, y0), CGPointMake(0, y1),
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g);
    CGColorSpaceRelease(space);
}

static UIColor *white(CGFloat a) {
    return [UIColor colorWithWhite:1 alpha:a];
}

static UIColor *black(CGFloat a) {
    return [UIColor colorWithWhite:0 alpha:a];
}

CGFloat TMGlassPad(TMGlassStyle style) {
    switch (style) {
    case TMGlassStyleBar: return 18;
    case TMGlassStyleButton: return 5;
    case TMGlassStylePanel: return 22;
    case TMGlassStyleLens: return 0;
    }
    return 0;
}

UIImage *TMGlassImage(TMGlassStyle style, CGFloat radius, BOOL pressed) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    BOOL dark = [TMTheme isDark];
    radius = MAX(1, round(radius * 2) / 2);
    NSString *key = [NSString stringWithFormat:@"%d|%.1f|%d|%d", (int)style, radius, dark, pressed];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;

    CGFloat pad = TMGlassPad(style), side = 2 * (radius + pad) + 2;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect shape = CGRectMake(pad, pad, side - 2 * pad, side - 2 * pad);
    CGPathRef path = roundedPath(shape, radius);

    UIColor *fill;
    CGFloat gloss, rimTop, rimBottom, edge;
    switch (style) {
    case TMGlassStyleLens:
        fill = dark ? white(0.14) : black(0.065);
        gloss = rimTop = rimBottom = edge = 0;
        break;
    case TMGlassStylePanel:
        fill = dark ? [UIColor colorWithRed:0.15 green:0.15 blue:0.16 alpha:0.97] : [UIColor colorWithRed:0.985 green:0.985 blue:0.99 alpha:0.97];
        gloss = dark ? 0.05 : 0.5;
        rimTop = dark ? 0.2 : 1;
        rimBottom = dark ? 0.05 : 0.6;
        edge = dark ? 0.6 : 0.08;
        break;
    default:
        if (pressed) {
            fill = dark ? [UIColor colorWithRed:0.26 green:0.26 blue:0.27 alpha:0.92] : [UIColor colorWithRed:0.86 green:0.86 blue:0.88 alpha:0.9];
        } else {
            fill = dark ? [UIColor colorWithRed:0.13 green:0.13 blue:0.14 alpha:0.92] : white(0.9);
        }
        gloss = dark ? 0.07 : 0.55;
        rimTop = dark ? 0.24 : 1;
        rimBottom = dark ? 0.04 : 0.45;
        edge = dark ? 0.55 : 0.07;
        break;
    }

    // Shadow under the fill
    CGContextSaveGState(c);
    if (style == TMGlassStyleBar || style == TMGlassStylePanel) {
        CGContextSetShadowWithColor(c, CGSizeMake(0, style == TMGlassStyleBar ? 5 : 8), style == TMGlassStyleBar ? 14 : 18,
                                    black(dark ? 0.5 : 0.13).CGColor);
    } else if (style == TMGlassStyleButton) {
        CGContextSetShadowWithColor(c, CGSizeMake(0, 1.5), 4, black(dark ? 0.45 : 0.12).CGColor);
    }
    CGContextAddPath(c, path);
    [fill setFill];
    CGContextFillPath(c);
    CGContextRestoreGState(c);

    // Gloss: light on the upper half
    if (gloss > 0) {
        CGContextSaveGState(c);
        CGContextAddPath(c, path);
        CGContextClip(c);
        verticalGradient(c, shape.origin.y, CGRectGetMidY(shape), white(gloss * 0.6), white(0));
        CGContextRestoreGState(c);
    }
    // Rim: a bright inner line that fades towards the bottom
    if (rimTop > 0) {
        CGPathRef rim = roundedPath(CGRectInset(shape, 0.75, 0.75), MAX(radius - 0.75, 0.5));
        CGContextSaveGState(c);
        CGContextAddPath(c, rim);
        CGContextSetLineWidth(c, 1.2);
        CGContextReplacePathWithStrokedPath(c);
        CGContextClip(c);
        verticalGradient(c, shape.origin.y, CGRectGetMaxY(shape), white(rimTop), white(rimBottom));
        CGContextRestoreGState(c);
        CGPathRelease(rim);
    }
    // Hairline edge so the glass reads on a page of the same colour
    if (edge > 0) {
        CGContextAddPath(c, path);
        CGContextSetLineWidth(c, 0.5);
        [black(edge) setStroke];
        CGContextStrokePath(c);
    }
    CGPathRelease(path);
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGFloat cap = radius + pad;
    img = TMStretchable(img, UIEdgeInsetsMake(cap, cap, cap, cap));
    [cache setObject:img forKey:key];
    return img;
}

UIImage *TMRoundImage(UIColor *fill, CGFloat radius) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    radius = MAX(0.5, round(radius * 2) / 2);
    NSString *key = [NSString stringWithFormat:@"%@|%.1f", fill, radius];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    CGFloat side = 2 * radius + 2;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGPathRef path = roundedPath(CGRectMake(0, 0, side, side), radius);
    CGContextAddPath(c, path);
    [fill setFill];
    CGContextFillPath(c);
    CGPathRelease(path);
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    img = TMStretchable(img, UIEdgeInsetsMake(radius, radius, radius, radius));
    [cache setObject:img forKey:key];
    return img;
}

static void observeTheme(id target) {
    [[NSNotificationCenter defaultCenter] addObserver:target
                                             selector:@selector(applyTheme)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
}

#pragma mark - Glass view

@implementation TMGlassView {
    UIImageView *_image;
    CGFloat _shownRadius;
    BOOL _shownDark, _shownPressed;
}

- (instancetype)initWithStyle:(TMGlassStyle)style radius:(CGFloat)radius {
    if ((self = [super initWithFrame:CGRectZero])) {
        _style = style;
        _radius = radius;
        _shownRadius = -1;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _image = [[UIImageView alloc] init];
        [self addSubview:_image];
        observeTheme(self);
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    _shownRadius = -1;
    [self setNeedsLayout];
}

- (void)setPressed:(BOOL)pressed {
    if (pressed == _pressed) return;
    _pressed = pressed;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pad = TMGlassPad(_style);
    _image.frame = CGRectInset(self.bounds, -pad, -pad);
    CGFloat r = _radius < 0 ? self.bounds.size.height / 2 : _radius;
    BOOL dark = [TMTheme isDark];
    if (r != _shownRadius || dark != _shownDark || _pressed != _shownPressed) {
        _shownRadius = r;
        _shownDark = dark;
        _shownPressed = _pressed;
        _image.image = TMGlassImage(_style, r, _pressed);
    }
}

@end

#pragma mark - Glass button

@implementation TMGlassButton {
    TMGlassView *_glass;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _glassInset = 4;
        _iconSize = 20;
        _glass = [[TMGlassView alloc] initWithStyle:TMGlassStyleButton radius:-1];
        [self insertSubview:_glass atIndex:0];
        self.titleLabel.font = TMFontMedium(15);
        self.adjustsImageWhenHighlighted = NO;
        observeTheme(self);
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)buttonWithIcon:(NSString *)icon target:(id)target action:(SEL)action {
    TMGlassButton *b = [[self alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    b.iconName = icon;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    TMGlassButton *b = [[self alloc] initWithFrame:CGRectZero];
    [b setTitle:title forState:UIControlStateNormal];
    CGSize s = [title sizeWithFont:b.titleLabel.font];
    b.frame = CGRectMake(0, 0, ceil(s.width) + 2 * b.glassInset + 28, 44);
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [b applyTheme];
    return b;
}

- (void)setIconName:(NSString *)iconName {
    _iconName = [iconName copy];
    [self applyTheme];
}

- (void)setTint:(UIColor *)tint {
    _tint = tint;
    [self applyTheme];
}

- (void)applyTheme {
    UIColor *c = self.tint ?: [TMTheme current].text;
    if (_iconName) [self setImage:TMIcon(_iconName, _iconSize, c) forState:UIControlStateNormal];
    [self setTitleColor:c forState:UIControlStateNormal];
    [_glass setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    _glass.pressed = highlighted;
    [UIView animateWithDuration:0.12 animations:^{
        self->_glass.transform = highlighted ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity;
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGAffineTransform t = _glass.transform;
    _glass.transform = CGAffineTransformIdentity;
    _glass.frame = CGRectInset(self.bounds, _glassInset, _glassInset);
    _glass.transform = t;
    [self sendSubviewToBack:_glass];
}

@end

#pragma mark - Pill

@implementation TMPill {
    CGFloat _imagesForHeight;
    BOOL _imagesDark;
}

+ (instancetype)pillWithTitle:(NSString *)title icon:(NSString *)icon style:(TMPillStyle)style target:(id)target action:(SEL)action {
    TMPill *p = [self buttonWithType:UIButtonTypeCustom];
    p.titleLabel.font = TMFontMedium(14);
    p.adjustsImageWhenHighlighted = NO;
    [p setTitle:title forState:UIControlStateNormal];
    p->_iconName = [icon copy];
    p->_pillStyle = style;
    if (target) [p addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    observeTheme(p);
    [p applyTheme];
    p.frame = CGRectMake(0, 0, [p fittingWidth], 36);
    return p;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setTitle:(NSString *)title {
    [self setTitle:title forState:UIControlStateNormal];
    [self setNeedsLayout];
}

- (void)setIconName:(NSString *)iconName {
    _iconName = [iconName copy];
    [self applyTheme];
}

- (void)setPillStyle:(TMPillStyle)pillStyle {
    _pillStyle = pillStyle;
    [self applyTheme];
}

- (UIColor *)fillColor:(BOOL)pressed {
    TMTheme *t = [TMTheme current];
    switch (_pillStyle) {
    case TMPillStyleBrand: return pressed ? [t.brand colorWithAlphaComponent:0.75] : t.brand;
    case TMPillStyleInverse: return pressed ? [t.inverse colorWithAlphaComponent:0.75] : t.inverse;
    default: return pressed ? t.elevatedPressed : t.elevated;
    }
}

- (UIColor *)contentColor {
    TMTheme *t = [TMTheme current];
    switch (_pillStyle) {
    case TMPillStyleBrand: return [UIColor whiteColor];
    case TMPillStyleInverse: return t.inverseText;
    default: return t.text;
    }
}

- (void)applyTheme {
    UIColor *c = [self contentColor];
    [self setTitleColor:c forState:UIControlStateNormal];
    [self setImage:_iconName ? TMIcon(_iconName, 18, c) : nil forState:UIControlStateNormal];
    _imagesForHeight = 0;
    [self setNeedsLayout];
}

- (CGFloat)fittingWidth {
    CGSize s = [[self titleForState:UIControlStateNormal] sizeWithFont:self.titleLabel.font];
    return ceil(s.width) + (_iconName ? 24 : 0) + 30;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    BOOL dark = [TMTheme isDark];
    if (h != _imagesForHeight || dark != _imagesDark) {
        _imagesForHeight = h;
        _imagesDark = dark;
        [self setBackgroundImage:TMRoundImage([self fillColor:NO], h / 2) forState:UIControlStateNormal];
        [self setBackgroundImage:TMRoundImage([self fillColor:YES], h / 2) forState:UIControlStateHighlighted];
    }
    // Icon + title centred as one group
    CGSize ts = [self.titleLabel.text sizeWithFont:self.titleLabel.font];
    CGFloat tw = MIN(ceil(ts.width), self.bounds.size.width - 24 - (_iconName ? 24 : 0));
    CGFloat iw = _iconName ? 18 : 0, gap = _iconName ? 6 : 0;
    CGFloat x = floor((self.bounds.size.width - iw - gap - tw) / 2);
    if (_iconName) self.imageView.frame = CGRectMake(x, floor((h - 18) / 2), 18, 18);
    self.titleLabel.frame = CGRectMake(x + iw + gap, floor((h - ceil(ts.height)) / 2), tw, ceil(ts.height));
}

@end

#pragma mark - Chips

@implementation TMChipBar {
    NSMutableArray *_chips;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.showsHorizontalScrollIndicator = NO;
        self.showsVerticalScrollIndicator = NO;
        self.alwaysBounceHorizontal = YES;
        self.scrollsToTop = NO;
        _chips = [NSMutableArray array];
        observeTheme(self);
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setTitles:(NSArray *)titles {
    _titles = [titles copy];
    for (UIView *v in _chips) [v removeFromSuperview];
    [_chips removeAllObjects];
    for (NSString *title in titles) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.titleLabel.font = TMFontMedium(14);
        [b setTitle:title forState:UIControlStateNormal];
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [_chips addObject:b];
    }
    [self applyTheme];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self applyTheme];
}

- (void)tapped:(UIButton *)b {
    NSInteger i = (NSInteger)[_chips indexOfObject:b];
    if (i == _selectedIndex) return;
    self.selectedIndex = i;
    if (self.onSelect) self.onSelect(i);
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    for (NSUInteger i = 0; i < _chips.count; i++) {
        UIButton *b = _chips[i];
        BOOL sel = (NSInteger)i == _selectedIndex;
        [b setTitleColor:sel ? t.inverseText : t.text forState:UIControlStateNormal];
        [b setBackgroundImage:TMRoundImage(sel ? t.inverse : t.elevated, 16) forState:UIControlStateNormal];
        [b setBackgroundImage:TMRoundImage(sel ? t.inverse : t.elevatedPressed, 16) forState:UIControlStateHighlighted];
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = TMIsPhone() ? 12 : 20, h = 32, y = floor((self.bounds.size.height - h) / 2);
    for (UIButton *b in _chips) {
        CGSize s = [[b titleForState:UIControlStateNormal] sizeWithFont:b.titleLabel.font];
        CGFloat w = ceil(s.width) + 28;
        b.frame = CGRectMake(x, y, w, h);
        x += w + 8;
    }
    self.contentSize = CGSizeMake(x + 4, self.bounds.size.height);
}

@end

#pragma mark - Segmented control

@implementation TMSegmentedControl {
    NSMutableArray *_labels;
    UIImageView *_track, *_thumb;
}

static const CGFloat kThumbInset = 2;

- (instancetype)initWithItems:(NSArray *)titles {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 200, 34)])) {
        _track = [[UIImageView alloc] init];
        [self addSubview:_track];
        _thumb = [[UIImageView alloc] init];
        [self addSubview:_thumb];
        _labels = [NSMutableArray array];
        for (NSString *title in titles) {
            UILabel *l = [[UILabel alloc] init];
            l.text = title;
            l.textAlignment = TMAlignCenter;
            l.backgroundColor = [UIColor clearColor];
            l.font = TMFontMedium(14);
            TMLabelShrinkToFit(l, 0.75);
            [self addSubview:l];
            [_labels addObject:l];
        }
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)]];
        observeTheme(self);
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSUInteger)numberOfSegments {
    return _labels.count;
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    for (NSUInteger i = 0; i < _labels.count; i++) {
        UILabel *l = _labels[i];
        l.textColor = (NSInteger)i == _selectedSegmentIndex ? t.text : t.secondaryText;
    }
    [self setNeedsLayout];
    _track.image = nil; // redrawn in layoutSubviews
}

- (CGRect)thumbFrame {
    CGFloat n = MAX(_labels.count, 1u), w = (self.bounds.size.width - 2 * kThumbInset) / n;
    return CGRectMake(kThumbInset + w * MAX(_selectedSegmentIndex, 0), kThumbInset, w, self.bounds.size.height - 2 * kThumbInset);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    TMTheme *t = [TMTheme current];
    CGFloat h = self.bounds.size.height;
    _track.frame = self.bounds;
    _track.image = TMRoundImage(t.dark ? [UIColor colorWithRed:0.17 green:0.17 blue:0.18 alpha:1] : [UIColor colorWithRed:0.93 green:0.93 blue:0.94 alpha:1], h / 2);
    CGRect thumb = [self thumbFrame];
    CGFloat pad = [self thumbPad];
    // Light: a white raised glass pill; dark: a lighter grey pill on the dark track (as iOS draws it)
    _thumb.image = t.dark ? TMRoundImage([UIColor colorWithRed:0.39 green:0.39 blue:0.4 alpha:1], thumb.size.height / 2)
                          : TMGlassImage(TMGlassStyleButton, thumb.size.height / 2, NO);
    _thumb.frame = CGRectInset(thumb, -pad, -pad);
    CGFloat w = thumb.size.width;
    for (NSUInteger i = 0; i < _labels.count; i++) {
        [_labels[i] setFrame:CGRectMake(kThumbInset + w * i + 6, 0, w - 12, h)];
    }
}

- (void)setSelectedSegmentIndex:(NSInteger)index {
    [self setSelectedSegmentIndex:index animated:NO];
}

- (CGFloat)thumbPad {
    return [TMTheme isDark] ? 0 : TMGlassPad(TMGlassStyleButton);
}

- (void)setSelectedSegmentIndex:(NSInteger)index animated:(BOOL)animated {
    _selectedSegmentIndex = index;
    [self applyTheme];
    CGFloat pad = [self thumbPad];
    [UIView animateWithDuration:animated ? 0.22 : 0
                     animations:^{ self->_thumb.frame = CGRectInset([self thumbFrame], -pad, -pad); }];
}

- (void)tap:(UITapGestureRecognizer *)g {
    if (!_labels.count) return;
    CGFloat x = [g locationInView:self].x;
    NSInteger i = (NSInteger)floor(x / (self.bounds.size.width / _labels.count));
    i = MAX(0, MIN((NSInteger)_labels.count - 1, i));
    if (i == _selectedSegmentIndex) return;
    [self setSelectedSegmentIndex:i animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

#pragma mark - Switch

@implementation TMSwitch {
    UIImageView *_track, *_knob;
}

static const CGFloat kSwitchW = 56, kSwitchH = 30, kKnobW = 33, kKnobInset = 2;

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, kSwitchW, kSwitchH)])) {
        _track = [[UIImageView alloc] initWithFrame:self.bounds];
        [self addSubview:_track];
        _knob = [[UIImageView alloc] init];
        [self addSubview:_knob];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)]];
        observeTheme(self);
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(kSwitchW, kSwitchH);
}

- (CGRect)knobFrame {
    CGFloat pad = TMGlassPad(TMGlassStyleButton), kh = kSwitchH - 2 * kKnobInset;
    CGFloat x = _on ? kSwitchW - kKnobInset - kKnobW : kKnobInset;
    return CGRectInset(CGRectMake(x, kKnobInset, kKnobW, kh), -pad, -pad);
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    UIColor *off = t.dark ? [UIColor colorWithRed:0.22 green:0.22 blue:0.24 alpha:1] : [UIColor colorWithRed:0.91 green:0.91 blue:0.92 alpha:1];
    _track.image = TMRoundImage(_on ? t.switchOn : off, kSwitchH / 2);
    _knob.image = [self knobImage];
    _knob.frame = [self knobFrame];
}

/// White pill with a soft shadow (same in both themes, like iOS).
- (UIImage *)knobImage {
    static UIImage *img;
    if (img) return img;
    CGFloat pad = TMGlassPad(TMGlassStyleButton), kh = kSwitchH - 2 * kKnobInset;
    CGSize size = CGSizeMake(kKnobW + 2 * pad, kh + 2 * pad);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1.5), 3.5, [UIColor colorWithWhite:0 alpha:0.25].CGColor);
    CGPathRef p = roundedPath(CGRectMake(pad, pad, kKnobW, kh), kh / 2);
    CGContextAddPath(c, p);
    [[UIColor whiteColor] setFill];
    CGContextFillPath(c);
    CGPathRelease(p);
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    [UIView animateWithDuration:animated ? 0.2 : 0
                     animations:^{ [self applyTheme]; }];
}

- (void)tap {
    [self setOn:!_on animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

#pragma mark - Pull to refresh

@implementation TMRefreshControl {
    __weak UIScrollView *_scroll;
    UIActivityIndicatorView *_spin;
    CAShapeLayer *_ring;
    CGFloat _baseTop;
}

static const CGFloat kRefreshH = 60, kTrigger = 72;

- (instancetype)initWithScrollView:(UIScrollView *)sv {
    if ((self = [super initWithFrame:CGRectMake(0, -kRefreshH, sv.bounds.size.width, kRefreshH)])) {
        _scroll = sv;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.backgroundColor = [UIColor clearColor];
        _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spin.hidesWhenStopped = YES;
        _spin.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [self addSubview:_spin];
        _ring = [CAShapeLayer layer];
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathAddArc(p, NULL, 11, 11, 10, -M_PI_2, 3 * M_PI_2, NO);
        _ring.path = p;
        CGPathRelease(p);
        _ring.fillColor = [UIColor clearColor].CGColor;
        _ring.lineWidth = 2.5;
        _ring.lineCap = kCALineCapRound;
        _ring.strokeEnd = 0;
        _ring.bounds = CGRectMake(0, 0, 22, 22);
        [self.layer addSublayer:_ring];
        [sv addSubview:self];
        observeTheme(self);
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    _spin.activityIndicatorViewStyle = t.spinnerStyle;
    _ring.strokeColor = t.secondaryText.CGColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGPoint c = CGPointMake(floor(self.bounds.size.width / 2), kRefreshH / 2 + 4);
    _spin.center = c;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ring.position = c;
    [CATransaction commit];
}

- (void)scrollViewDidScroll {
    UIScrollView *sv = _scroll;
    if (!sv || _refreshing) return;
    CGFloat pulled = -(sv.contentOffset.y + sv.contentInset.top);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ring.strokeEnd = MAX(0, MIN(1, (pulled - 12) / (kTrigger - 12)));
    _ring.opacity = pulled > 12 ? 1 : 0;
    [CATransaction commit];
}

- (void)scrollViewDidEndDragging {
    UIScrollView *sv = _scroll;
    if (!sv || _refreshing) return;
    if (-(sv.contentOffset.y + sv.contentInset.top) < kTrigger) return;
    _refreshing = YES;
    _ring.opacity = 0;
    [_spin startAnimating];
    _baseTop = sv.contentInset.top;
    [UIView animateWithDuration:0.2
                     animations:^{
                         UIEdgeInsets inset = sv.contentInset;
                         inset.top = self->_baseTop + kRefreshH;
                         sv.contentInset = inset;
                     }];
    if (self.onRefresh) self.onRefresh();
}

- (void)endRefreshing {
    if (!_refreshing) return;
    _refreshing = NO;
    [_spin stopAnimating];
    UIScrollView *sv = _scroll;
    [UIView animateWithDuration:0.25
                     animations:^{
                         UIEdgeInsets inset = sv.contentInset;
                         inset.top = self->_baseTop;
                         sv.contentInset = inset;
                     }];
}

@end

#pragma mark - Text field

@implementation TMTextField

- (void)drawPlaceholderInRect:(CGRect)rect {
    [[TMTheme current].secondaryText setFill];
    UIFont *font = self.font ?: TMFontRegular(17);
    CGSize s = [self.placeholder sizeWithFont:font];
    CGRect r = CGRectMake(rect.origin.x, rect.origin.y + floor((rect.size.height - s.height) / 2), rect.size.width, s.height);
    [self.placeholder drawInRect:r withFont:font lineBreakMode:TMLineBreakTail alignment:self.textAlignment];
}

@end

#pragma mark - Slider

void TMStyleSlider(UISlider *slider, UIColor *fill) {
    UIColor *rest = [TMTheme isDark] ? [UIColor colorWithWhite:1 alpha:0.22] : [UIColor colorWithWhite:0 alpha:0.14];
    UIImage *min = TMRoundImage(fill, 1.5), *max = TMRoundImage(rest, 1.5);
    [slider setMinimumTrackImage:min forState:UIControlStateNormal];
    [slider setMaximumTrackImage:max forState:UIControlStateNormal];
    static UIImage *knob;
    if (!knob) {
        CGFloat d = 13, pad = 4;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(d + 2 * pad, d + 2 * pad), NO, 0);
        CGContextRef c = UIGraphicsGetCurrentContext();
        CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 2.5, [UIColor colorWithWhite:0 alpha:0.3].CGColor);
        [[UIColor whiteColor] setFill];
        CGContextFillEllipseInRect(c, CGRectMake(pad, pad, d, d));
        knob = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    [slider setThumbImage:knob forState:UIControlStateNormal];
    [slider setThumbImage:knob forState:UIControlStateHighlighted];
}
