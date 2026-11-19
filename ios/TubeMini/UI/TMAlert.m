#import "TMAlert.h"
#import "TMCompat.h"
#import "TMGlass.h"
#import "TMLog.h"
#import "TMTheme.h"
#import <QuartzCore/QuartzCore.h>

static NSMutableArray *gShown;

typedef NS_ENUM(NSInteger, TMAlertButtonKind) { TMAlertButtonPrimary, TMAlertButtonCancel, TMAlertButtonDestructive };

@implementation TMAlert {
    BOOL _sheet;
    UIView *_dim;
    TMGlassView *_cardGlass, *_cancelGlass;
    UIView *_card, *_cancelCard;
    UIView *_rows; // sheet choices (a plain view: a UIScrollView here left a dangling pointer in UIKit on iOS 6 after the sheet closed)
    UILabel *_title, *_message;
    NSMutableArray *_buttonViews, *_lines;
    UIButton *_cancelButton;
    UIView *_titleLine;
    NSArray *_buttons;
    NSInteger _cancelIndex, _destructiveIndex;
    TMAlertHandler _handler;
    BOOL _closing;
}

#pragma mark - Public

+ (void)showTitle:(NSString *)title message:(NSString *)message button:(NSString *)button {
    [self showTitle:title message:message buttons:@[ button ?: @"OK" ] cancelIndex:-1 destructiveIndex:-1 handler:nil];
}

+ (void)showTitle:(NSString *)title
          message:(NSString *)message
          buttons:(NSArray *)buttons
      cancelIndex:(NSInteger)cancelIndex
 destructiveIndex:(NSInteger)destructiveIndex
          handler:(TMAlertHandler)handler {
    TMAlert *a = [[TMAlert alloc] initSheet:NO title:title message:message buttons:buttons cancel:cancelIndex destructive:destructiveIndex];
    a->_handler = [handler copy];
    [a present];
}

+ (void)sheetWithTitle:(NSString *)title buttons:(NSArray *)buttons destructiveIndex:(NSInteger)destructiveIndex handler:(TMAlertHandler)handler {
    TMAlert *a = [[TMAlert alloc] initSheet:YES title:title message:nil buttons:buttons cancel:-1 destructive:destructiveIndex];
    a->_handler = [handler copy];
    [a present];
}

+ (void)dismissAll {
    for (TMAlert *a in [gShown copy]) {
        TMLog(@"[debug] %@: %@ — %@ [%@]", a->_sheet ? @"sheet" : @"alert", a->_title.text ?: @"", a->_message.text ?: @"",
              [a->_buttons componentsJoinedByString:@" | "]);
        [a finish:a->_sheet ? -1 : a->_cancelIndex animated:NO];
    }
}

#pragma mark - Building

- (UILabel *)label:(UIFont *)font lines:(NSInteger)lines {
    UILabel *l = [[UILabel alloc] init];
    l.font = font;
    l.numberOfLines = lines;
    l.textAlignment = TMAlignCenter;
    l.backgroundColor = [UIColor clearColor];
    l.lineBreakMode = TMLineBreakWord;
    return l;
}

- (TMAlertButtonKind)kindOf:(NSInteger)i {
    if (i == _destructiveIndex) return TMAlertButtonDestructive;
    if (i == _cancelIndex) return TMAlertButtonCancel;
    return TMAlertButtonPrimary;
}

- (instancetype)initSheet:(BOOL)sheet title:(NSString *)title message:(NSString *)message buttons:(NSArray *)buttons
                   cancel:(NSInteger)cancel destructive:(NSInteger)destructive {
    if ((self = [super initWithFrame:CGRectZero])) {
        _sheet = sheet;
        _buttons = [buttons copy];
        _cancelIndex = cancel;
        _destructiveIndex = destructive;
        TMTheme *t = [TMTheme current];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dim = [[UIView alloc] init];
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:t.dark ? 0.5 : 0.28];
        [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dimTapped)]];
        [self addSubview:_dim];

        _card = [[UIView alloc] init];
        _cardGlass = [[TMGlassView alloc] initWithStyle:TMGlassStylePanel radius:sheet ? 22 : 26];
        [_card addSubview:_cardGlass];
        [self addSubview:_card];

        if (title.length) {
            _title = [self label:sheet ? TMFontMedium(13) : TMFontBold(17) lines:0];
            _title.text = title;
            _title.textColor = sheet ? t.secondaryText : t.text;
            [_card addSubview:_title];
            if (sheet) {
                _titleLine = [[UIView alloc] init];
                _titleLine.backgroundColor = t.separator;
                [_card addSubview:_titleLine];
            }
        }
        if (message.length) {
            _message = [self label:TMFontRegular(14) lines:0];
            _message.text = message;
            _message.textColor = t.secondaryText;
            [_card addSubview:_message];
        }
        _buttonViews = [NSMutableArray array];
        _lines = [NSMutableArray array];
        if (sheet) {
            _rows = [[UIView alloc] init];
            _rows.backgroundColor = [UIColor clearColor];
            [_card addSubview:_rows];
        }
        for (NSUInteger i = 0; i < buttons.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            [b setTitle:buttons[i] forState:UIControlStateNormal];
            b.titleLabel.lineBreakMode = TMLineBreakTail;
            b.tag = (NSInteger)i;
            [b addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            TMAlertButtonKind kind = [self kindOf:(NSInteger)i];
            if (sheet) {
                b.titleLabel.font = TMFontRegular(18);
                [b setTitleColor:kind == TMAlertButtonDestructive ? t.destructive : t.accent forState:UIControlStateNormal];
                [b setBackgroundImage:[TMTheme imageWithColor:t.dark ? [UIColor colorWithWhite:1 alpha:0.08] : [UIColor colorWithWhite:0 alpha:0.06]]
                             forState:UIControlStateHighlighted];
                [_rows addSubview:b];
                if (i > 0) {
                    UIView *line = [[UIView alloc] init];
                    line.backgroundColor = t.separator;
                    [_rows addSubview:line];
                    [_lines addObject:line];
                }
            } else {
                b.titleLabel.font = kind == TMAlertButtonCancel ? TMFontMedium(16) : TMFontBold(16);
                UIColor *fill = kind == TMAlertButtonPrimary ? t.accent : t.elevated;
                UIColor *text = kind == TMAlertButtonPrimary ? [UIColor whiteColor] : (kind == TMAlertButtonDestructive ? t.destructive : t.text);
                [b setTitleColor:text forState:UIControlStateNormal];
                [b setBackgroundImage:TMRoundImage(fill, 22) forState:UIControlStateNormal];
                [b setBackgroundImage:TMRoundImage(kind == TMAlertButtonPrimary ? [fill colorWithAlphaComponent:0.75] : t.elevatedPressed, 22)
                             forState:UIControlStateHighlighted];
                [_card addSubview:b];
            }
            [_buttonViews addObject:b];
        }
        if (sheet) {
            _cancelCard = [[UIView alloc] init];
            _cancelGlass = [[TMGlassView alloc] initWithStyle:TMGlassStylePanel radius:-1];
            [_cancelCard addSubview:_cancelGlass];
            _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
            [_cancelButton setTitle:@"Huỷ" forState:UIControlStateNormal];
            _cancelButton.titleLabel.font = TMFontBold(18);
            [_cancelButton setTitleColor:t.accent forState:UIControlStateNormal];
            [_cancelButton setTitleColor:[t.accent colorWithAlphaComponent:0.5] forState:UIControlStateHighlighted];
            [_cancelButton addTarget:self action:@selector(dimTapped) forControlEvents:UIControlEventTouchUpInside];
            [_cancelCard addSubview:_cancelButton];
            [self addSubview:_cancelCard];
        }
    }
    return self;
}

#pragma mark - Layout

- (CGFloat)heightOf:(UILabel *)l width:(CGFloat)w {
    if (!l) return 0;
    return ceil([l.text sizeWithFont:l.font constrainedToSize:CGSizeMake(w, 2000) lineBreakMode:TMLineBreakWord].height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _dim.frame = self.bounds;
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    if (_sheet) {
        [self layoutSheetWidth:W height:H];
    } else {
        [self layoutAlertWidth:W height:H];
    }
}

- (void)layoutAlertWidth:(CGFloat)W height:(CGFloat)H {
    CGFloat w = MIN(300, W - 40), inner = w - 40, y = 22;
    if (_title) {
        CGFloat h = [self heightOf:_title width:inner];
        _title.frame = CGRectMake(20, y, inner, h);
        y += h + 6;
    }
    if (_message) {
        CGFloat h = MIN([self heightOf:_message width:inner], H * 0.5);
        _message.frame = CGRectMake(20, y, inner, h);
        y += h;
    }
    y += 18;
    CGFloat bw = w - 28, bh = 44;
    if (_buttonViews.count == 2) {
        CGFloat half = floor((bw - 8) / 2);
        // Cancel on the left, like iOS
        NSInteger left = _cancelIndex == 1 ? 1 : 0;
        [_buttonViews[(NSUInteger)left] setFrame:CGRectMake(14, y, half, bh)];
        [_buttonViews[(NSUInteger)(1 - left)] setFrame:CGRectMake(14 + half + 8, y, half, bh)];
        y += bh;
    } else {
        for (UIButton *b in _buttonViews) {
            b.frame = CGRectMake(14, y, bw, bh);
            y += bh + 8;
        }
        y -= 8;
    }
    y += 14;
    _card.bounds = CGRectMake(0, 0, w, y);
    _card.center = CGPointMake(floor(W / 2), floor(H / 2));
    _cardGlass.frame = _card.bounds;
}

- (void)layoutSheetWidth:(CGFloat)W height:(CGFloat)H {
    CGFloat w = MIN(W - 16, 420), x = floor((W - w) / 2), y = 0;
    if (_title) {
        CGFloat h = MIN([self heightOf:_title width:w - 32], 80);
        _title.frame = CGRectMake(16, 14, w - 32, h);
        y = h + 26;
    }
    // Rows get shorter when many choices meet a short screen (iPhone on its side)
    CGFloat room = H - 8 - 56 - 8 - y - 20, n = MAX(_buttonViews.count, 1u);
    CGFloat rowH = floor(MAX(36, MIN(54, room / n)));
    _rows.frame = CGRectMake(0, y, w, rowH * _buttonViews.count);
    for (NSUInteger i = 0; i < _buttonViews.count; i++) {
        [_buttonViews[i] setFrame:CGRectMake(0, i * rowH, w, rowH)];
        if (i > 0) [_lines[i - 1] setFrame:CGRectMake(0, i * rowH, w, 1 / [UIScreen mainScreen].scale)];
    }
    _titleLine.frame = CGRectMake(0, y, w, 1 / [UIScreen mainScreen].scale);
    CGFloat cardH = y + _rows.frame.size.height;
    CGFloat cancelH = 56, bottom = H - 8;
    _cancelCard.frame = CGRectMake(x, bottom - cancelH, w, cancelH);
    _cancelGlass.frame = _cancelCard.bounds;
    _cancelButton.frame = _cancelCard.bounds;
    _card.frame = CGRectMake(x, CGRectGetMinY(_cancelCard.frame) - 8 - cardH, w, cardH);
    _cardGlass.frame = _card.bounds;
    // Row highlights stay inside the rounded card
    _card.layer.cornerRadius = 22;
    _card.clipsToBounds = NO;
    _rows.layer.cornerRadius = _title ? 0 : 22;
    _rows.clipsToBounds = YES;
}

#pragma mark - Showing

+ (UIView *)host {
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    NSArray *windows = [UIApplication sharedApplication].windows;
    if (!vc && windows.count) vc = [windows[0] rootViewController];
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc.view;
}

- (void)present {
    UIView *host = [TMAlert host];
    if (!host) return;
    if (!gShown) gShown = [NSMutableArray array];
    [gShown addObject:self];
    [host endEditing:YES];
    self.frame = host.bounds;
    [host addSubview:self];
    [self layoutIfNeeded];
    _dim.alpha = 0;
    if (_sheet) {
        CGFloat drop = self.bounds.size.height - CGRectGetMinY(_card.frame);
        _card.transform = CGAffineTransformMakeTranslation(0, drop);
        _cancelCard.transform = CGAffineTransformMakeTranslation(0, drop);
    } else {
        _card.alpha = 0;
        _card.transform = CGAffineTransformMakeScale(1.1, 1.1);
    }
    [UIView animateWithDuration:_sheet ? 0.3 : 0.22
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         self->_dim.alpha = 1;
                         self->_card.alpha = 1;
                         self->_card.transform = CGAffineTransformIdentity;
                         self->_cancelCard.transform = CGAffineTransformIdentity;
                     }
                     completion:nil];
}

- (void)finish:(NSInteger)index animated:(BOOL)animated {
    if (_closing) return;
    _closing = YES;
    [gShown removeObject:self];
    TMAlertHandler handler = _handler;
    _handler = nil;
    void (^remove)(BOOL) = ^(BOOL done) { [self removeFromSuperview]; };
    if (animated) {
        CGFloat drop = self.bounds.size.height - CGRectGetMinY(_card.frame);
        [UIView animateWithDuration:0.2
                         animations:^{
                             self->_dim.alpha = 0;
                             if (self->_sheet) {
                                 self->_card.transform = CGAffineTransformMakeTranslation(0, drop);
                                 self->_cancelCard.transform = CGAffineTransformMakeTranslation(0, drop);
                             } else {
                                 self->_card.alpha = 0;
                                 self->_card.transform = CGAffineTransformMakeScale(0.95, 0.95);
                             }
                         }
                         completion:remove];
    } else {
        remove(YES);
    }
    if (handler && (index >= 0 || _sheet)) handler(index);
}

- (void)buttonTapped:(UIButton *)b {
    [self finish:b.tag animated:YES];
}

- (void)dimTapped {
    if (_sheet) [self finish:-1 animated:YES];
}

@end
