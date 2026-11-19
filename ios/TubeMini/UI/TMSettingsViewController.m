#import "TMSettingsViewController.h"
#import "TMAlert.h"
#import "TMAPIClient.h"
#import "TMAudioBar.h"
#import "TMCompat.h"
#import "TMGlass.h"
#import "TMIcons.h"
#import "TMLog.h"
#import "TMNavigationController.h"
#import "TMTheme.h"
#import "TMUpdater.h"
#import <QuartzCore/QuartzCore.h>
#include <arpa/inet.h>
#include <netinet/in.h>

enum { kSectionServer, kSectionQuality, kSectionProxy, kSectionTheme, kSectionUpdate, kSectionTelegram, kSectionCount };
enum { kRowServer, kRowToken, kRowDiscover, kRowTest };

typedef NS_ENUM(NSInteger, TMCardPosition) { TMCardSingle, TMCardTop, TMCardMiddle, TMCardBottom };

/// Left / right inset of the cards: 16 pt on an iPhone, a readable column (≤ 640 pt) on the iPad.
static CGFloat cardMargin(CGFloat width) {
    return TMIsPhone() ? 16 : MAX(40, floor((width - 640) / 2));
}

/// A card segment: all corners rounded (single row), the top ones, none, or the bottom ones.
static UIImage *cardImage(UIColor *fill, TMCardPosition pos) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    NSString *key = [NSString stringWithFormat:@"%@|%d", fill, (int)pos];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    CGFloat r = 14, side = 2 * r + 2;
    UIRectCorner corners = pos == TMCardSingle ? UIRectCornerAllCorners
                           : pos == TMCardTop  ? (UIRectCornerTopLeft | UIRectCornerTopRight)
                           : pos == TMCardBottom ? (UIRectCornerBottomLeft | UIRectCornerBottomRight)
                                                 : 0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [fill setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) byRoundingCorners:corners cornerRadii:CGSizeMake(r, r)] fill];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    img = TMStretchable(img, UIEdgeInsetsMake(r, r, r, r));
    [cache setObject:img forKey:key];
    return img;
}

/// Coloured rounded square with a white glyph (the iOS Settings icon tiles).
static UIImage *iconTile(NSString *icon, UIColor *colour) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    NSString *key = [NSString stringWithFormat:@"%@|%@", icon, colour];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    CGFloat s = 30;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [colour setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:7.5] fill];
    [TMIcon(icon, 20, [UIColor whiteColor]) drawInRect:CGRectMake(5, 5, 20, 20)];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [cache setObject:img forKey:key];
    return img;
}

static UIColor *rgb(int r, int g, int b) {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
}

#pragma mark - Card cell

/// One row of a card: optional icon tile, title, and a control at the right (or filling the row).
@interface TMFormCell : UITableViewCell
@property (nonatomic) TMCardPosition position;
@property (nonatomic, strong) UIImage *tile;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) BOOL action;            // tappable row (accent title)
@property (nonatomic, strong) UIView *control; // right side, or the whole row when `fill`
@property (nonatomic) BOOL fill;
@property (nonatomic, strong) UIView *spinner;
@end

@implementation TMFormCell {
    UIImageView *_back, *_pressed, *_tileView;
    UILabel *_label;
    UIView *_line;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) {
        self.backgroundColor = [UIColor clearColor];
        _back = [[UIImageView alloc] init];
        self.backgroundView = _back;
        _pressed = [[UIImageView alloc] init];
        self.selectedBackgroundView = _pressed;
        _tileView = [[UIImageView alloc] init];
        [self.contentView addSubview:_tileView];
        _label = [[UILabel alloc] init];
        _label.backgroundColor = [UIColor clearColor];
        _label.font = TMFontRegular(17);
        [self.contentView addSubview:_label];
        _line = [[UIView alloc] init];
        [self.contentView addSubview:_line];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)setControl:(UIView *)control {
    [_control removeFromSuperview];
    _control = control;
    if (control) [self.contentView addSubview:control];
}

- (void)setSpinner:(UIView *)spinner {
    [_spinner removeFromSuperview];
    _spinner = spinner;
    if (spinner) [self.contentView addSubview:spinner];
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    _back.image = cardImage(t.cellBackground, _position);
    _pressed.image = cardImage(t.dark ? rgb(52, 52, 56) : rgb(225, 225, 230), _position);
    _label.textColor = _action ? t.accent : t.text;
    _label.text = _text;
    _tileView.image = _tile;
    _line.backgroundColor = t.separator;
    _line.hidden = _position == TMCardSingle || _position == TMCardBottom;
    self.selectionStyle = _action ? UITableViewCellSelectionStyleGray : UITableViewCellSelectionStyleNone;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Same card inset on iOS 5–8 (grouped cells are inset by UIKit on iOS 5/6 only, and differently)
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height, m = cardMargin(W);
    CGRect card = CGRectMake(m, 0, W - 2 * m, H);
    _back.frame = card;
    _pressed.frame = card;
    self.contentView.frame = card;
    CGFloat x = 16, cw = card.size.width;
    if (_tile) {
        _tileView.frame = CGRectMake(14, floor((H - 30) / 2), 30, 30);
        x = 14 + 30 + 12;
    }
    _tileView.hidden = !_tile;
    if (_fill) {
        _control.frame = CGRectMake(x - (_tile ? 0 : 4), 0, cw - x - 10 + (_tile ? 0 : 4), H);
        if ([_control isKindOfClass:[TMSegmentedControl class]]) _control.frame = CGRectMake(12, floor((H - 34) / 2), cw - 24, 34);
        _label.frame = CGRectZero;
    } else {
        CGSize cs = _control.bounds.size;
        _control.frame = CGRectMake(cw - 14 - cs.width, floor((H - cs.height) / 2), cs.width, cs.height);
        CGFloat right = _control ? CGRectGetMinX(_control.frame) - 8 : cw - 14;
        if (_spinner) {
            _spinner.center = CGPointMake(cw - 28, H / 2);
            if ([(UIActivityIndicatorView *)_spinner isAnimating]) right = cw - 48;
        }
        _label.frame = CGRectMake(x, 0, right - x, H);
    }
    CGFloat px = 1 / [UIScreen mainScreen].scale;
    _line.frame = CGRectMake(x, H - px, cw - x, px);
}

@end

#pragma mark - Telegram

/// "Nhóm Telegram": QR code + handle. Telegram's servers need newer TLS than iOS 5/6 have, so a link
/// would not open on the device; the QR code is meant for a phone camera.
@interface TMTelegramCell : TMFormCell
@property (nonatomic, readonly) UILabel *handle, *link, *info;
+ (CGFloat)heightForTableWidth:(CGFloat)width;
@end

@implementation TMTelegramCell {
    UIImageView *_qr;
}

static const CGFloat kQRSize = 145; // 29 modules × 5 pt: crisp at 1x and 2x

- (UILabel *)labelWithFont:(UIFont *)font {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.backgroundColor = [UIColor clearColor];
    l.font = font;
    [self.contentView addSubview:l];
    return l;
}

- (instancetype)init {
    if ((self = [super init])) {
        _qr = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"telegram-qr.png"]];
        _qr.layer.cornerRadius = 8;
        _qr.layer.masksToBounds = YES;
        [self.contentView addSubview:_qr];
        _handle = [self labelWithFont:TMFontBold(20)];
        _handle.text = @"@tivikit";
        _link = [self labelWithFont:TMFontRegular(16)];
        _link.text = @"t.me/tivikit";
        _info = [self labelWithFont:TMFontRegular(14)];
        _info.numberOfLines = 0;
        _info.text = @"Hỏi cách cài, báo lỗi, góp ý tính năng và nhận tin khi có bản mới. iOS cũ không mở được Telegram: "
                     @"quét mã này bằng camera điện thoại, hoặc tìm @tivikit trong Telegram.";
    }
    return self;
}

/// Narrow cards (iPhone portrait) put the text under the code.
+ (BOOL)stacked:(CGFloat)cardWidth {
    return cardWidth < 440;
}

+ (CGFloat)heightForTableWidth:(CGFloat)width {
    return [self stacked:width - 2 * cardMargin(width)] ? 310 : 175;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    NSArray *labels = @[ _handle, _link, _info ];
    if ([TMTelegramCell stacked:b.size.width]) {
        _qr.frame = CGRectMake(floor((b.size.width - kQRSize) / 2), 14, kQRSize, kQRSize);
        for (UILabel *l in labels) l.textAlignment = TMAlignCenter;
        _handle.frame = CGRectMake(14, 168, b.size.width - 28, 24);
        _link.frame = CGRectMake(14, 192, b.size.width - 28, 20);
        _info.frame = CGRectMake(14, 216, b.size.width - 28, b.size.height - 224);
    } else {
        _qr.frame = CGRectMake(14, floor((b.size.height - kQRSize) / 2), kQRSize, kQRSize);
        CGFloat x = 14 + kQRSize + 18, w = b.size.width - x - 16;
        for (UILabel *l in labels) l.textAlignment = TMAlignLeft;
        _handle.frame = CGRectMake(x, 20, w, 26);
        _link.frame = CGRectMake(x, 48, w, 22);
        CGSize fit = [_info sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
        _info.frame = CGRectMake(x, 78, w, MIN(ceil(fit.height), b.size.height - 78 - 10));
    }
}

@end

#pragma mark - Controller

@interface TMSettingsViewController () <TMGroupedScreen>
@end

@implementation TMSettingsViewController {
    TMTextField *_server, *_token;
    TMSegmentedControl *_quality, *_theme;
    TMSwitch *_proxy;
    UIActivityIndicatorView *_spin, *_discoverSpin, *_updateSpin;
    UILabel *_version;
    BOOL _testing, _searching;
    NSNetServiceBrowser *_browser;
    NSMutableArray *_services; // NSNetService being resolved (must stay alive)
    NSMutableArray *_found;    // @[name, url]
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Cài đặt";
    }
    return self;
}

- (TMTextField *)fieldWithPlaceholder:(NSString *)placeholder {
    TMTextField *f = [[TMTextField alloc] initWithFrame:CGRectZero];
    f.placeholder = placeholder;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    f.font = TMFontRegular(17);
    f.delegate = self;
    [f addTarget:self action:@selector(save) forControlEvents:UIControlEventEditingDidEnd];
    return f;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    TMSetLargeTitle(self, @"Cài đặt", NO);
    TMAPIClient *api = [TMAPIClient shared];
    _server = [self fieldWithPlaceholder:@"http://192.168.1.10:8080"];
    _server.keyboardType = UIKeyboardTypeURL;
    _server.text = api.serverURL;
    _token = [self fieldWithPlaceholder:@"Mã truy cập (nếu có)"];
    _token.secureTextEntry = YES;
    _token.text = api.token;
    _quality = [[TMSegmentedControl alloc] initWithItems:@[ @"360p", @"720p", @"1080p" ]];
    _quality.selectedSegmentIndex = (NSInteger)[[TMAPIClient qualities] indexOfObject:@(api.preferredQuality)];
    [_quality addTarget:self action:@selector(save) forControlEvents:UIControlEventValueChanged];
    _theme = [[TMSegmentedControl alloc] initWithItems:@[ @"Sáng", @"Tối" ]];
    _theme.selectedSegmentIndex = [TMTheme isDark] ? 1 : 0;
    [_theme addTarget:self action:@selector(themePicked) forControlEvents:UIControlEventValueChanged];
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _discoverSpin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _updateSpin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _proxy = [[TMSwitch alloc] init];
    _proxy.on = api.useProxy;
    [_proxy addTarget:self action:@selector(proxyToggled) forControlEvents:UIControlEventValueChanged];

    _version = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 44)];
    _version.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _version.backgroundColor = [UIColor clearColor];
    _version.textAlignment = TMAlignCenter;
    _version.font = TMFontRegular(13);
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    _version.text = [NSString stringWithFormat:@"TubeMini %@ · iOS %@", info[@"CFBundleShortVersionString"], [UIDevice currentDevice].systemVersion];
    self.tableView.tableFooterView = _version;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updaterChanged)
                                                 name:TMUpdaterDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [TMAudioBar applyInsetTo:self.tableView];
    [self applyTheme];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)themePicked {
    [TMTheme setDark:_theme.selectedSegmentIndex == 1];
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = t.groupedBackground;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    for (UITextField *f in @[ _server, _token ]) {
        f.textColor = t.text;
        f.keyboardAppearance = t.keyboard;
        [f setNeedsDisplay];
    }
    _theme.selectedSegmentIndex = t.dark ? 1 : 0;
    for (UIActivityIndicatorView *s in @[ _spin, _discoverSpin, _updateSpin ]) s.activityIndicatorViewStyle = t.spinnerStyle;
    _version.textColor = t.tertiaryText;
    [self.tableView reloadData];
}

/// Section titles and notes, aligned with the text inside the cards.
- (UIView *)sectionLabel:(NSString *)text header:(BOOL)header {
    if (!text.length) return nil;
    CGFloat W = self.tableView.bounds.size.width, x = cardMargin(W) + 16;
    CGFloat h = header ? 38 : [self footerHeight:text];
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, h)];
    box.backgroundColor = [UIColor clearColor];
    UILabel *l = [[UILabel alloc] initWithFrame:header ? CGRectMake(x, 12, W - 2 * x, 22) : CGRectMake(x, 6, W - 2 * x, h - 14)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.backgroundColor = [UIColor clearColor];
    l.numberOfLines = header ? 1 : 0;
    l.text = text;
    l.font = header ? TMFontMedium(14) : TMFontRegular(13);
    l.textColor = [TMTheme current].secondaryText;
    [box addSubview:l];
    return box;
}

/// Footers grow with their text.
- (CGFloat)footerHeight:(NSString *)text {
    if (!text.length) return 14;
    CGFloat W = self.tableView.bounds.size.width, w = W - 2 * (cardMargin(W) + 16);
    CGSize s = [text sizeWithFont:TMFontRegular(13) constrainedToSize:CGSizeMake(w, 1000) lineBreakMode:TMLineBreakWord];
    return ceil(s.height) + 22;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [self sectionLabel:[self tableView:tableView titleForHeaderInSection:section] header:YES];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [self sectionLabel:[self tableView:tableView titleForFooterInSection:section] header:NO];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView titleForHeaderInSection:section].length ? 38 : 14;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return [self footerHeight:[self tableView:tableView titleForFooterInSection:section]];
}

- (void)reloadFields {
    TMAPIClient *api = [TMAPIClient shared];
    _server.text = api.serverURL;
    _token.text = api.token;
    _quality.selectedSegmentIndex = (NSInteger)[[TMAPIClient qualities] indexOfObject:@(api.preferredQuality)];
    _proxy.on = api.useProxy;
}

- (void)proxyToggled {
    [TMAPIClient shared].useProxy = _proxy.on;
    TMLog(@"[settings] phát qua máy chủ: %@", _proxy.on ? @"bật" : @"tắt");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadFields];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self save];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    // Card insets, the Telegram cell and the notes depend on the width
    [self.tableView reloadData];
}

- (void)save {
    TMAPIClient *api = [TMAPIClient shared];
    api.serverURL = _server.text;
    api.token = _token.text;
    api.preferredQuality = [[TMAPIClient qualities][(NSUInteger)MAX(_quality.selectedSegmentIndex, 0)] integerValue];
    _server.text = api.serverURL; // show the normalized form
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == kSectionServer ? 4 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
    case kSectionServer: return @"Máy chủ";
    case kSectionQuality: return @"Chất lượng mặc định";
    case kSectionProxy: return @"Ở ngoài mạng nhà";
    case kSectionTheme: return @"Giao diện";
    case kSectionUpdate: return @"Cập nhật ứng dụng";
    case kSectionTelegram: return @"Nhóm Telegram";
    default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
    case kSectionServer:
        return @"Máy chạy tubemini-server trong mạng nhà, ví dụ http://192.168.1.10:8080. Tự tìm chỉ được khi máy này và máy chủ "
               @"ở chung một mạng (cùng dải địa chỉ IP).";
    case kSectionUpdate:
        return [NSString stringWithFormat:@"Đang dùng TubeMini %@. Cũng cập nhật được trong Cydia: nguồn https://tubemini.github.io/cydia/",
                                          [TMUpdater currentVersion]];
    case kSectionProxy: return @"Bật khi xem bằng 4G hay Wi-Fi khác mà video không phát: video sẽ đi qua máy chủ (tốn mạng nhà). Máy chủ phải đặt proxy_fallback = true.";
    case kSectionQuality: return @"360p nhẹ và ổn định. 720p cần Wi-Fi tốt, 1080p cần Wi-Fi rất tốt (khoảng 5 Mbit/s). Video không có mức đã chọn thì phát mức thấp hơn gần nhất.";
    default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionTelegram) return [TMTelegramCell heightForTableWidth:tableView.bounds.size.width];
    return 52;
}

- (TMCardPosition)positionOf:(NSIndexPath *)ip {
    NSInteger n = [self tableView:self.tableView numberOfRowsInSection:ip.section];
    if (n == 1) return TMCardSingle;
    if (ip.row == 0) return TMCardTop;
    return ip.row == n - 1 ? TMCardBottom : TMCardMiddle;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TMTheme *t = [TMTheme current];
    TMFormCell *cell;
    if (indexPath.section == kSectionTelegram) {
        TMTelegramCell *tg = [[TMTelegramCell alloc] init];
        tg.handle.textColor = t.text;
        tg.link.textColor = t.accent;
        tg.info.textColor = t.secondaryText;
        cell = tg;
    } else {
        cell = [[TMFormCell alloc] init];
    }
    cell.position = [self positionOf:indexPath];
    switch (indexPath.section) {
    case kSectionServer:
        switch (indexPath.row) {
        case kRowServer:
            cell.tile = iconTile(@"globe", rgb(0, 122, 255));
            cell.control = _server;
            cell.fill = YES;
            break;
        case kRowToken:
            cell.tile = iconTile(@"key", rgb(142, 142, 147));
            cell.control = _token;
            cell.fill = YES;
            break;
        case kRowDiscover:
            cell.tile = iconTile(@"wifi", rgb(52, 170, 220));
            cell.text = _searching ? @"Đang tìm…" : @"Tìm máy chủ trong mạng";
            cell.action = YES;
            _searching ? [_discoverSpin startAnimating] : [_discoverSpin stopAnimating];
            cell.spinner = _discoverSpin;
            break;
        case kRowTest:
            cell.tile = iconTile(@"bolt", rgb(52, 199, 89));
            cell.text = _testing ? @"Đang kiểm tra…" : @"Kiểm tra kết nối";
            cell.action = YES;
            _testing ? [_spin startAnimating] : [_spin stopAnimating];
            cell.spinner = _spin;
            break;
        }
        break;
    case kSectionQuality:
        cell.control = _quality;
        cell.fill = YES;
        break;
    case kSectionTheme:
        cell.control = _theme;
        cell.fill = YES;
        break;
    case kSectionProxy:
        cell.tile = iconTile(@"antenna", rgb(255, 149, 0));
        cell.text = @"Phát qua máy chủ";
        cell.control = _proxy;
        break;
    case kSectionUpdate: {
        TMUpdater *u = [TMUpdater shared];
        cell.tile = iconTile(@"update", rgb(255, 45, 85));
        cell.text = u.busy ? u.status : (u.updateAvailable ? [NSString stringWithFormat:@"Cập nhật lên %@", u.latestVersion] : @"Kiểm tra cập nhật");
        cell.action = YES;
        u.busy ? [_updateSpin startAnimating] : [_updateSpin stopAnimating];
        cell.spinner = _updateSpin;
        break;
    }
    }
    [cell applyTheme];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == kSectionServer && indexPath.row == kRowTest) [self testConnection];
    if (indexPath.section == kSectionServer && indexPath.row == kRowDiscover) [self discover];
    if (indexPath.section == kSectionUpdate) [self updateTapped];
}

#pragma mark - App update

- (void)updaterChanged {
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSectionUpdate] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)updateTapped {
    TMUpdater *u = [TMUpdater shared];
    if (u.busy) return;
    if (u.updateAvailable) {
        [u offer];
        return;
    }
    [u check:^(NSString *error) {
        if (error) {
            [TMAlert showTitle:@"Không kiểm tra được" message:error button:@"Đóng"];
        } else if (u.updateAvailable) {
            [u offer];
        } else {
            [TMAlert showTitle:@"Đang dùng bản mới nhất" message:[NSString stringWithFormat:@"TubeMini %@", [TMUpdater currentVersion]] button:@"OK"];
        }
    }];
}

#pragma mark - Bonjour

- (void)discover {
    if (_searching) return;
    [self.view endEditing:YES];
    _searching = YES;
    _found = [NSMutableArray array];
    _services = [NSMutableArray array];
    _browser = [[NSNetServiceBrowser alloc] init];
    _browser.delegate = self;
    [_browser searchForServicesOfType:@"_tubemini._tcp." inDomain:@"local."];
    TMLog(@"[settings] tìm máy chủ (Bonjour)");
    [self.tableView reloadData];
    [self performSelector:@selector(discoveryDone) withObject:nil afterDelay:5];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)more {
    [_services addObject:service];
    service.delegate = self;
    [service resolveWithTimeout:4];
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    for (NSData *data in service.addresses) {
        const struct sockaddr *sa = data.bytes;
        if (data.length < sizeof(struct sockaddr_in) || sa->sa_family != AF_INET) continue;
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &((const struct sockaddr_in *)sa)->sin_addr, ip, sizeof ip);
        NSString *url = [NSString stringWithFormat:@"http://%s:%ld", ip, (long)service.port];
        BOOL seen = NO;
        for (NSArray *f in _found) seen = seen || [f[1] isEqualToString:url];
        if (!seen) [_found addObject:@[ service.name ?: @"TubeMini", url ]];
        TMLog(@"[settings] thấy %@ ở %@", service.name, url);
    }
}

- (void)discoveryDone {
    [_browser stop];
    _browser = nil;
    _searching = NO;
    [self.tableView reloadData];
    if (!_found.count) {
        [TMAlert showTitle:@"Không tìm thấy máy chủ"
                   message:@"Máy này và máy chủ phải ở chung một mạng (cùng dải địa chỉ IP), và máy chủ bật mdns = true. Nếu không, "
                           @"nhập địa chỉ bằng tay."
                    button:@"OK"];
    } else if (_found.count == 1) {
        [self useServer:_found[0][1]];
    } else {
        NSMutableArray *titles = [NSMutableArray array];
        for (NSArray *f in _found) [titles addObject:[NSString stringWithFormat:@"%@ — %@", f[0], f[1]]];
        NSArray *found = [_found copy];
        [TMAlert sheetWithTitle:@"Chọn máy chủ"
                        buttons:titles
               destructiveIndex:-1
                        handler:^(NSInteger i) {
                            if (i >= 0 && i < (NSInteger)found.count) [self useServer:found[(NSUInteger)i][1]];
                        }];
    }
}

- (void)useServer:(NSString *)url {
    _server.text = url;
    [self testConnection]; // saves, then pings
}

- (void)testConnection {
    [self.view endEditing:YES];
    [self save];
    if (_testing) return;
    _testing = YES;
    [self.tableView reloadData];
    [[TMAPIClient shared] ping:^(TMPing *ping, NSString *error) {
        self->_testing = NO;
        [self.tableView reloadData];
        NSString *title, *message;
        if (error) {
            title = @"Không kết nối được";
            message = error;
        } else {
            NSMutableArray *lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"Máy chủ TubeMini %@", ping.server]];
            [lines addObject:ping.ytdlp.length ? [NSString stringWithFormat:@"yt-dlp %@", ping.ytdlp]
                                               : @"⚠ Máy chủ thiếu yt-dlp: không phát được video."];
            [lines addObject:ping.deno.length ? @"Deno: có" : @"⚠ Máy chủ thiếu Deno: yt-dlp không lấy được link."];
            if ([TMAPIClient shared].useProxy) {
                [lines addObject:[ping.proxy isEqualToString:@"on"] ? @"Phát qua máy chủ: máy chủ cho phép."
                                                                    : @"⚠ Máy chủ chưa bật proxy_fallback: “Phát qua máy chủ” chưa có tác dụng."];
            }
            title = (ping.ytdlp.length && ping.deno.length) ? @"Kết nối tốt" : @"Kết nối được, nhưng thiếu công cụ";
            message = [lines componentsJoinedByString:@"\n"];
        }
        TMLog(@"[settings] kiểm tra kết nối: %@ — %@", title, message);
        [TMAlert showTitle:title message:message button:@"OK"];
    }];
}

@end
