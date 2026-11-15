#import "TMSettingsViewController.h"
#import "TMAPIClient.h"
#import "TMLog.h"
#import "TMTheme.h"
#include <arpa/inet.h>
#include <netinet/in.h>

enum {
    kSectionServer,
    kSectionDiscover,
    kSectionToken,
    kSectionQuality,
    kSectionProxy,
    kSectionTheme,
    kSectionTest,
    kSectionCount
};

@implementation TMSettingsViewController {
    UITextField *_server, *_token;
    UISegmentedControl *_quality, *_theme;
    UISwitch *_proxy;
    UIActivityIndicatorView *_spin, *_discoverSpin;
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
    [self.tableView reloadData];
}

/// Grouped section titles drawn in theme colours (iOS 6 draws them grey with a white shadow).
- (UIView *)sectionLabel:(NSString *)text header:(BOOL)header {
    if (!text.length) return nil;
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, header ? 44 : 60)];
    box.backgroundColor = [UIColor clearColor];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectInset(box.bounds, 50, header ? 6 : 4)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    l.backgroundColor = [UIColor clearColor];
    l.numberOfLines = 3;
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
    return [self tableView:tableView titleForFooterInSection:section].length ? 60 : 10;
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
    case kSectionTheme: return @"Giao diện";
    default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
    case kSectionServer: return @"Máy chạy tubemini-server trong mạng nhà, ví dụ http://192.168.1.10:8080";
    case kSectionDiscover: return @"Tự tìm chỉ được khi iPad và máy chủ ở chung một mạng (cùng dải địa chỉ IP).";
    case kSectionProxy: return @"Bật khi xem bằng 4G hay Wi-Fi khác mà video không phát: video sẽ đi qua máy chủ (tốn mạng nhà). Máy chủ phải đặt proxy_fallback = true.";
    case kSectionQuality: return @"360p nhẹ và ổn định. 720p (HD) cần Wi-Fi tốt, 1080p (Full HD) cần Wi-Fi rất tốt (khoảng 5 Mbit/s). Video không có mức đã chọn thì phát mức thấp hơn gần nhất. Video có quảng cáo phải chờ vài giây trước khi phát.";
    case kSectionTest: {
        NSDictionary *info = [NSBundle mainBundle].infoDictionary;
        return [NSString stringWithFormat:@"TubeMini %@ · iOS %@", info[@"CFBundleShortVersionString"],
                                          [UIDevice currentDevice].systemVersion];
    }
    default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
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
                                    message:@"iPad và máy chủ phải ở chung một mạng (cùng dải địa chỉ IP), và máy chủ bật "
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
