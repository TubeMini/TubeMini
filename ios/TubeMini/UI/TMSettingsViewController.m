#import "TMSettingsViewController.h"
#import "TMAPIClient.h"
#import "TMLog.h"
#import "TMTheme.h"
#import "TMUpdater.h"
#import <QuartzCore/QuartzCore.h>
#include <arpa/inet.h>
#include <netinet/in.h>

enum {
    kSectionServer,
    kSectionDiscover,
    kSectionToken,
    kSectionQuality,
    kSectionProxy,
    kSectionTheme,
    kSectionUpdate,
    kSectionTelegram,
    kSectionTest,
    kSectionCount
};

/// "Nhóm Telegram": QR code + handle. Telegram's servers need newer TLS than iOS 6 has, so a link would not
/// open on the iPad; the QR code is meant for a phone camera.
@interface TMTelegramCell : UITableViewCell
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
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _qr = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"telegram-qr.png"]];
        _qr.layer.cornerRadius = 6;
        _qr.layer.masksToBounds = YES;
        [self.contentView addSubview:_qr];
        _handle = [self labelWithFont:[UIFont boldSystemFontOfSize:20]];
        _handle.text = @"@tivikit";
        _link = [self labelWithFont:[UIFont systemFontOfSize:16]];
        _link.text = @"t.me/tivikit";
        _info = [self labelWithFont:[UIFont systemFontOfSize:14]];
        _info.numberOfLines = 0;
        _info.text = @"Hỏi cách cài, báo lỗi, góp ý tính năng và nhận tin khi có bản mới. iOS 6 không mở được Telegram: "
                     @"quét mã này bằng camera điện thoại, hoặc tìm @tivikit trong Telegram.";
    }
    return self;
}

/// Narrow screens (iPhone portrait) put the text under the code.
+ (BOOL)stacked:(CGFloat)width {
    return width < 440;
}

+ (CGFloat)heightForTableWidth:(CGFloat)width {
    return [self stacked:width - 20] ? 300 : 170;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    NSArray *labels = @[ _handle, _link, _info ];
    if ([TMTelegramCell stacked:b.size.width]) {
        _qr.frame = CGRectMake(floorf((b.size.width - kQRSize) / 2), 12, kQRSize, kQRSize);
        for (UILabel *l in labels) l.textAlignment = NSTextAlignmentCenter;
        _handle.frame = CGRectMake(12, 164, b.size.width - 24, 24);
        _link.frame = CGRectMake(12, 188, b.size.width - 24, 20);
        _info.frame = CGRectMake(12, 212, b.size.width - 24, b.size.height - 220);
    } else {
        _qr.frame = CGRectMake(12, floorf((b.size.height - kQRSize) / 2), kQRSize, kQRSize);
        CGFloat x = 12 + kQRSize + 18, w = b.size.width - x - 14;
        for (UILabel *l in labels) l.textAlignment = NSTextAlignmentLeft;
        _handle.frame = CGRectMake(x, 18, w, 26);
        _link.frame = CGRectMake(x, 46, w, 22);
        CGSize fit = [_info sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
        _info.frame = CGRectMake(x, 76, w, MIN(ceilf(fit.height), b.size.height - 76 - 10));
    }
}

@end

@implementation TMSettingsViewController {
    UITextField *_server, *_token;
    UISegmentedControl *_quality, *_theme;
    UISwitch *_proxy;
    UIActivityIndicatorView *_spin, *_discoverSpin, *_updateSpin;
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

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectZero];
    f.placeholder = placeholder;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    f.font = [UIFont systemFontOfSize:17];
    f.delegate = self;
    [f addTarget:self action:@selector(save) forControlEvents:UIControlEventEditingDidEnd];
    return f;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    TMAPIClient *api = [TMAPIClient shared];
    _server = [self fieldWithPlaceholder:@"http://192.168.1.10:8080"];
    _server.keyboardType = UIKeyboardTypeURL;
    _server.text = api.serverURL;
    _token = [self fieldWithPlaceholder:@"Để trống nếu máy chủ không đặt mã"];
    _token.secureTextEntry = YES;
    _token.text = api.token;
    _quality = [[UISegmentedControl alloc] initWithItems:@[ @"360p", @"720p", @"1080p" ]];
    _quality.selectedSegmentIndex = (NSInteger)[[TMAPIClient qualities] indexOfObject:@(api.preferredQuality)];
    _quality.segmentedControlStyle = UISegmentedControlStyleBar; // iOS 6 only tints the bar style
    [_quality addTarget:self action:@selector(save) forControlEvents:UIControlEventValueChanged];
    _theme = [[UISegmentedControl alloc] initWithItems:@[ @"Sáng", @"Tối" ]];
    _theme.selectedSegmentIndex = [TMTheme isDark] ? 1 : 0;
    _theme.segmentedControlStyle = UISegmentedControlStyleBar;
    [_theme addTarget:self action:@selector(themePicked) forControlEvents:UIControlEventValueChanged];
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _discoverSpin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _updateSpin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updaterChanged)
                                                 name:TMUpdaterDidChangeNotification
                                               object:nil];
    _proxy = [[UISwitch alloc] init];
    _proxy.on = api.useProxy;
    [_proxy addTarget:self action:@selector(proxyToggled) forControlEvents:UIControlEventValueChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
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
    [t styleTableView:self.tableView];
    for (UITextField *f in @[ _server, _token ]) {
        f.textColor = t.text;
        f.keyboardAppearance = t.keyboard;
    }
    UIColor *seg = t.dark ? [UIColor colorWithWhite:0.28 alpha:1] : [UIColor colorWithRed:0.62 green:0.08 blue:0.08 alpha:1];
    _quality.tintColor = seg;
    _theme.tintColor = seg;
    _theme.selectedSegmentIndex = t.dark ? 1 : 0;
    _spin.activityIndicatorViewStyle = t.dark ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;
    _discoverSpin.activityIndicatorViewStyle = _spin.activityIndicatorViewStyle;
    _updateSpin.activityIndicatorViewStyle = _spin.activityIndicatorViewStyle;
    [self.tableView reloadData];
}

/// Side inset of section titles, in line with the grouped cells: those start 45 pt in on the iPad, 10 pt on an
/// iPhone (in both orientations).
- (CGFloat)sectionLabelInset {
    return [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 20 : 50;
}

/// Footers grow with their text (3–5 lines at 320 pt on an iPhone).
- (CGFloat)footerHeight:(NSString *)text {
    if (!text.length) return 10;
    CGFloat w = self.tableView.bounds.size.width - 2 * [self sectionLabelInset];
    CGSize s = [text sizeWithFont:[UIFont systemFontOfSize:15] constrainedToSize:CGSizeMake(w, 1000) lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(60, ceil(s.height) + 16);
}

/// Grouped section titles drawn in theme colours (iOS 6 draws them grey with a white shadow).
- (UIView *)sectionLabel:(NSString *)text header:(BOOL)header {
    if (!text.length) return nil;
    CGFloat h = header ? 44 : [self footerHeight:text];
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, h)];
    box.backgroundColor = [UIColor clearColor];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectInset(box.bounds, [self sectionLabelInset], header ? 6 : 4)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    l.backgroundColor = [UIColor clearColor];
    l.numberOfLines = header ? 1 : 0;
    l.text = text;
    l.font = header ? [UIFont boldSystemFontOfSize:17] : [UIFont systemFontOfSize:15];
    l.textColor = header ? [TMTheme current].text : [TMTheme current].secondaryText;
    l.textAlignment = header ? NSTextAlignmentLeft : NSTextAlignmentCenter;
    [box addSubview:l];
    return box;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [self sectionLabel:[self tableView:tableView titleForHeaderInSection:section] header:YES];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [self sectionLabel:[self tableView:tableView titleForFooterInSection:section] header:NO];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView titleForHeaderInSection:section].length ? 44 : 10;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return [self footerHeight:[self tableView:tableView titleForFooterInSection:section]];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [TMTheme current].cellBackground; // iOS 6 grouped cells only take it here
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

- (BOOL)shouldAutorotate {
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    // Row and footer heights depend on the width (Telegram cell, footer text); recompute them without rebuilding the cells
    [self.tableView beginUpdates];
    [self.tableView endUpdates];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
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
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
    case kSectionServer: return @"Địa chỉ máy chủ";
    case kSectionToken: return @"Mã truy cập";
    case kSectionQuality: return @"Chất lượng mặc định";
    case kSectionProxy: return @"Ở ngoài mạng nhà";
    case kSectionUpdate: return @"Cập nhật ứng dụng";
    case kSectionTheme: return @"Giao diện";
    case kSectionTelegram: return @"Nhóm Telegram";
    default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
    case kSectionServer: return @"Máy chạy tubemini-server trong mạng nhà, ví dụ http://192.168.1.10:8080";
    case kSectionDiscover: return @"Tự tìm chỉ được khi máy này và máy chủ ở chung một mạng (cùng dải địa chỉ IP).";
    case kSectionUpdate:
        return [NSString stringWithFormat:@"Đang dùng TubeMini %@. Cũng cập nhật được trong Cydia: nguồn https://tubemini.github.io/cydia/",
                                          [TMUpdater currentVersion]];
    case kSectionProxy: return @"Bật khi xem bằng 4G hay Wi-Fi khác mà video không phát: video sẽ đi qua máy chủ (tốn mạng nhà). Máy chủ phải đặt proxy_fallback = true.";
    case kSectionQuality: return @"360p nhẹ và ổn định. 720p cần Wi-Fi tốt, 1080p cần Wi-Fi rất tốt (khoảng 5 Mbit/s). Video không có mức đã chọn thì phát mức thấp hơn gần nhất.";
    case kSectionTest: {
        NSDictionary *info = [NSBundle mainBundle].infoDictionary;
        return [NSString stringWithFormat:@"TubeMini %@ · iOS %@", info[@"CFBundleShortVersionString"],
                                          [UIDevice currentDevice].systemVersion];
    }
    default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionTelegram) return [TMTelegramCell heightForTableWidth:tableView.bounds.size.width];
    return tableView.rowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionTelegram) {
        TMTheme *t = [TMTheme current];
        TMTelegramCell *tg = [[TMTelegramCell alloc] init];
        tg.handle.textColor = t.text;
        tg.link.textColor = t.accent;
        tg.info.textColor = t.secondaryText;
        return tg;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    CGRect inset = CGRectInset(cell.contentView.bounds, 12, 4);
    UIView *control = nil;
    switch (indexPath.section) {
    case kSectionServer: control = _server; break;
    case kSectionToken: control = _token; break;
    case kSectionQuality: control = _quality; break;
    case kSectionTheme: control = _theme; break;
    case kSectionDiscover:
        cell.textLabel.text = _searching ? @"Đang tìm…" : @"Tìm máy chủ trong mạng";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [TMTheme current].accent;
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        _discoverSpin.center = CGPointMake(30, 22);
        _searching ? [_discoverSpin startAnimating] : [_discoverSpin stopAnimating];
        [cell.contentView addSubview:_discoverSpin];
        return cell;
    case kSectionUpdate: {
        TMUpdater *u = [TMUpdater shared];
        cell.textLabel.text = u.busy ? u.status : (u.updateAvailable ? [NSString stringWithFormat:@"Cập nhật lên %@", u.latestVersion]
                                                                     : @"Kiểm tra cập nhật");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [TMTheme current].accent;
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        _updateSpin.center = CGPointMake(30, 22);
        u.busy ? [_updateSpin startAnimating] : [_updateSpin stopAnimating];
        [cell.contentView addSubview:_updateSpin];
        return cell;
    }
    case kSectionProxy:
        cell.textLabel.text = @"Phát qua máy chủ";
        cell.textLabel.textColor = [TMTheme current].text;
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.accessoryView = _proxy;
        return cell;
    case kSectionTest:
        cell.textLabel.text = _testing ? @"Đang kiểm tra…" : @"Kiểm tra kết nối";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [TMTheme current].accent;
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        _spin.center = CGPointMake(30, 22);
        _testing ? [_spin startAnimating] : [_spin stopAnimating];
        [cell.contentView addSubview:_spin];
        return cell;
    }
    control.frame = inset;
    control.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [cell.contentView addSubview:control];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == kSectionTest) [self testConnection];
    if (indexPath.section == kSectionDiscover) [self discover];
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
            [[[UIAlertView alloc] initWithTitle:@"Không kiểm tra được" message:error delegate:nil cancelButtonTitle:@"Đóng"
                              otherButtonTitles:nil] show];
        } else if (u.updateAvailable) {
            [u offer];
        } else {
            [[[UIAlertView alloc] initWithTitle:@"Đang dùng bản mới nhất"
                                        message:[NSString stringWithFormat:@"TubeMini %@", [TMUpdater currentVersion]]
                                       delegate:nil
                              cancelButtonTitle:@"OK"
                              otherButtonTitles:nil] show];
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
        [[[UIAlertView alloc] initWithTitle:@"Không tìm thấy máy chủ"
                                    message:@"Máy này và máy chủ phải ở chung một mạng (cùng dải địa chỉ IP), và máy chủ bật "
                                            @"mdns = true. Nếu không, nhập địa chỉ bằng tay."
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    } else if (_found.count == 1) {
        [self useServer:_found[0][1]];
    } else {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chọn máy chủ"
                                                           delegate:self
                                                  cancelButtonTitle:nil
                                             destructiveButtonTitle:nil
                                                  otherButtonTitles:nil];
        for (NSArray *f in _found) [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@ — %@", f[0], f[1]]];
        CGRect r = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:kSectionDiscover]];
        [sheet showFromRect:r inView:self.tableView animated:YES];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex >= 0 && buttonIndex < (NSInteger)_found.count) [self useServer:_found[(NSUInteger)buttonIndex][1]];
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
        [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    }];
}

@end
