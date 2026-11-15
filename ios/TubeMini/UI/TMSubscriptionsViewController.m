#import "TMSubscriptionsViewController.h"
#import "TMLibrary.h"

static void showError(NSString *title, NSString *message) {
    [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"Đóng" otherButtonTitles:nil] show];
}

#pragma mark - Subscriptions

@implementation TMSubscriptionsViewController {
    BOOL _stale; // the list changed elsewhere: reload when shown
}

- (instancetype)init {
    TMFirstPageBlock first = ^(TMFeedBlock done) {
        [[TMAPIClient shared] subscriptions:^(TMFeed *feed, NSString *error) {
            if (feed) [[TMLibrary shared] updateWithChannels:feed.entries];
            done(feed, error);
        }];
    };
    if ((self = [super initWithTitle:@"Đã theo dõi" firstPage:first])) {
        self.emptyMessage = @"Chưa theo dõi kênh nào.\nMở một kênh (từ Tìm kiếm hoặc trang video) rồi bấm “+ Theo dõi”.";
        self.deleteTitle = @"Bỏ theo dõi";
        __weak TMSubscriptionsViewController *weakSelf = self;
        self.onDelete = ^(id item) {
            TMChannel *c = item;
            [[TMLibrary shared] setSubscribed:NO
                                    channelID:c.channelID
                                   completion:^(NSString *error) {
                                       if (!error) return;
                                       showError(@"Không bỏ theo dõi được", error);
                                       [weakSelf reload];
                                   }];
        };
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(changed)
                                                     name:TMSubscriptionsDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)changed {
    _stale = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_stale) {
        _stale = NO;
        [self reload];
    }
}

@end

#pragma mark - History

@implementation TMHistoryViewController {
    BOOL _stale;
}

- (instancetype)init {
    if ((self = [super initWithTitle:@"Lịch sử" firstPage:^(TMFeedBlock done) { [[TMAPIClient shared] history:done]; }])) {
        self.emptyMessage = @"Chưa xem video nào.";
        self.deleteTitle = @"Xoá";
        self.onDelete = ^(id item) {
            [[TMAPIClient shared] forgetHistory:[item videoID]
                                     completion:^(NSString *error) {
                                         if (error) showError(@"Không xoá được", error);
                                     }];
        };
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(changed)
                                                     name:TMHistoryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Xoá hết" style:UIBarButtonItemStyleBordered target:self action:@selector(askClear)];
}

- (void)changed {
    _stale = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_stale) {
        _stale = NO;
        [self reload];
    }
}

- (void)askClear {
    if (!self.items.count) return;
    [[[UIAlertView alloc] initWithTitle:@"Xoá toàn bộ lịch sử xem?"
                                message:@"Vị trí đang xem dở của mọi video cũng mất."
                               delegate:self
                      cancelButtonTitle:@"Không"
                      otherButtonTitles:@"Xoá hết", nil] show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != alertView.cancelButtonIndex) [self clearAll];
}

- (void)clearAll {
    [[TMAPIClient shared] forgetHistory:nil
                             completion:^(NSString *error) {
                                 if (error) showError(@"Không xoá được", error);
                                 [self reload];
                             }];
}

@end
