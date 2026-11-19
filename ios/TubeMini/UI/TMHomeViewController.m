#import "TMHomeViewController.h"
#import "TMAPIClient.h"
#import "TMCompat.h"
#import "TMGlass.h"
#import "TMLibrary.h"
#import "TMListViewController.h"
#import "TMNavigationController.h"
#import "TMTheme.h"

static NSString *const kGridKey = @"TMHomeGrid";
static NSString *const kSourceKey = @"TMHomeSubscriptions";

@implementation TMHomeViewController {
    TMListViewController *_list;
    TMChipBar *_chips;
    TMGlassButton *_modeButton;
    BOOL _fresh; // next load asks the server to refetch every channel
    BOOL _stale; // the source changed while Home was hidden
}

- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSNumber *saved = [d objectForKey:kSourceKey];
        _subscriptionsSource = saved ? saved.boolValue : [TMLibrary shared].subscriptionCount > 0;
        NSNumber *grid = [d objectForKey:kGridKey];
        _gridMode = grid ? grid.boolValue : YES; // cards, unless the user picked rows before
        __weak TMHomeViewController *weakSelf = self;
        _list = [[TMListViewController alloc] initWithTitle:@"Trang chủ"
                                                  firstPage:^(TMFeedBlock done) { [weakSelf loadFirstPage:done]; }];
        _list.willRefresh = ^{ [weakSelf markFresh]; };
        _list.cards = _gridMode;
        [self updateEmptyMessage];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    TMSetLargeTitle(self, @"TubeMini", YES);
    self.title = @"Trang chủ";
    _modeButton = [TMGlassButton buttonWithIcon:_gridMode ? @"list" : @"grid" target:self action:@selector(toggleMode)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithCustomView:_modeButton],
        TMBarButton(@"refresh", self, @selector(refresh)),
    ];
    [self addChildViewController:_list];
    _list.view.frame = self.view.bounds;
    _list.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_list.view];
    [_list didMoveToParentViewController:self];

    // Chips scroll away with the feed, like YouTube's
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [UIColor clearColor];
    _chips = [[TMChipBar alloc] initWithFrame:CGRectMake(0, 2, header.bounds.size.width, 44)];
    _chips.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _chips.titles = @[ @"Đã theo dõi", @"Phổ biến" ];
    _chips.selectedIndex = _subscriptionsSource ? 0 : 1;
    __weak TMHomeViewController *weakSelf = self;
    _chips.onSelect = ^(NSInteger i) { [weakSelf setSubscriptionsSource:i == 0]; };
    [header addSubview:_chips];
    _list.tableView.tableHeaderView = header;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(subscriptionsChanged)
                                                 name:TMSubscriptionsDidChangeNotification
                                               object:nil];
    [self themeChanged];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)themeChanged {
    self.view.backgroundColor = [TMTheme current].background;
}

#pragma mark - Source

- (void)loadFirstPage:(TMFeedBlock)done {
    BOOL fresh = _fresh;
    _fresh = NO;
    if (_subscriptionsSource) {
        [[TMAPIClient shared] subscriptionFeed:fresh completion:done];
    } else {
        [[TMAPIClient shared] popular:done];
    }
}

- (void)markFresh {
    _fresh = _subscriptionsSource;
}

- (void)updateEmptyMessage {
    _list.emptyMessage = _subscriptionsSource ? @"Chưa có video từ kênh đã theo dõi.\nMở một kênh (từ Tìm kiếm hoặc trang video) rồi "
                                                @"bấm “Theo dõi”: video mới của kênh sẽ hiện ở đây."
                                              : @"Máy chủ chưa có video phổ biến.";
}

- (void)setSubscriptionsSource:(BOOL)subscriptions {
    _subscriptionsSource = subscriptions;
    _chips.selectedIndex = subscriptions ? 0 : 1;
    [[NSUserDefaults standardUserDefaults] setBool:subscriptions forKey:kSourceKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateEmptyMessage];
    [_list reload];
}

/// A channel was (un)subscribed: the subscriptions feed is out of date.
- (void)subscriptionsChanged {
    if (!_subscriptionsSource) return;
    if (self.isViewLoaded && self.view.window) {
        [_list reload];
    } else {
        _stale = YES;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_stale) {
        _stale = NO;
        [_list reload];
    }
}

#pragma mark - Cards / rows

- (UIViewController *)activeChild {
    return _list;
}

- (void)setGridMode:(BOOL)grid {
    _gridMode = grid;
    _modeButton.iconName = grid ? @"list" : @"grid";
    [[NSUserDefaults standardUserDefaults] setBool:grid forKey:kGridKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    _list.cards = grid;
}

- (void)toggleMode {
    [self setGridMode:!_gridMode];
}

- (void)refresh {
    [self markFresh];
    [_list reload];
    [_list.tableView setContentOffset:CGPointMake(0, -_list.tableView.contentInset.top) animated:YES];
}

@end
