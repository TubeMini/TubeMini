#import "TMSettingsViewController.h"
#import "TMAPIClient.h"
#import "TMLog.h"
#import "TMTheme.h"

enum { kSectionServer, kSectionToken, kSectionQuality, kSectionTheme, kSectionTest, kSectionCount };

@implementation TMSettingsViewController {
    UITextField *_server, *_token;
    UISegmentedControl *_quality, *_theme;
    UIActivityIndicatorView *_spin;
    BOOL _testing;
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
    _quality = [[UISegmentedControl alloc] initWithItems:@[ @"360p", @"720p" ]];
    _quality.selectedSegmentIndex = api.preferredQuality >= 720 ? 1 : 0;
    _quality.segmentedControlStyle = UISegmentedControlStyleBar; // iOS 6 only tints the bar style
    [_quality addTarget:self action:@selector(save) forControlEvents:UIControlEventValueChanged];
    _theme = [[UISegmentedControl alloc] initWithItems:@[ @"Sáng", @"Tối" ]];
    _theme.selectedSegmentIndex = [TMTheme isDark] ? 1 : 0;
    _theme.segmentedControlStyle = UISegmentedControlStyleBar;
    [_theme addTarget:self action:@selector(themePicked) forControlEvents:UIControlEventValueChanged];
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
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
    _quality.selectedSegmentIndex = api.preferredQuality >= 720 ? 1 : 0;
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
    api.preferredQuality = _quality.selectedSegmentIndex == 1 ? 720 : 360;
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
    case kSectionTheme: return @"Giao diện";
    default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
    case kSectionServer: return @"Máy chạy tubemini-server trong mạng nhà, ví dụ http://192.168.1.10:8080";
    case kSectionQuality: return @"360p nhẹ và ổn định. 720p (HD) cần Wi-Fi tốt; video có quảng cáo phải chờ vài giây trước khi phát.";
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
            title = (ping.ytdlp.length && ping.deno.length) ? @"Kết nối tốt" : @"Kết nối được, nhưng thiếu công cụ";
            message = [lines componentsJoinedByString:@"\n"];
        }
        TMLog(@"[settings] kiểm tra kết nối: %@ — %@", title, message);
        [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    }];
}

@end
