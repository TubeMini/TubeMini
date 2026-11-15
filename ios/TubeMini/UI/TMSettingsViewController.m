#import "TMSettingsViewController.h"
#import "TMAPIClient.h"
#import "TMLog.h"

enum { kSectionServer, kSectionToken, kSectionQuality, kSectionTest, kSectionCount };

@implementation TMSettingsViewController {
    UITextField *_server, *_token;
    UISegmentedControl *_quality;
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
    [_quality addTarget:self action:@selector(save) forControlEvents:UIControlEventValueChanged];
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
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
    case kSectionTest:
        cell.textLabel.text = _testing ? @"Đang kiểm tra…" : @"Kiểm tra kết nối";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor colorWithRed:0.2 green:0.33 blue:0.55 alpha:1];
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
