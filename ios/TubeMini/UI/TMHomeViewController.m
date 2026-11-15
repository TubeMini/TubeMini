#import "TMHomeViewController.h"
#import "TMAPIClient.h"
#import "TMGridViewController.h"
#import "TMLibrary.h"
#import "TMListViewController.h"
#import "TMTheme.h"

static NSString *const kGridKey = @"TMHomeGrid";
static NSString *const kSourceKey = @"TMHomeSubscriptions";

@implementation TMHomeViewController {
    TMListViewController *_list;
    TMGridViewController *_grid;
    UISegmentedControl *_mode, *_source;
    BOOL _fresh;               // next load asks the server to refetch every channel
    BOOL _listStale, _gridStale; // the source changed while that view was hidden
}

- (instancetype)init {
    if ((self = [super init])) {
        self.title = @"Trang chủ";
        NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:kSourceKey];
        _subscriptionsSource = saved ? saved.boolValue : [TMLibrary shared].subscriptionCount > 0;
        __weak TMHomeViewController *weakSelf = self;
        TMFirstPageBlock first = ^(TMFeedBlock done) { [weakSelf loadFirstPage:done]; };
        _list = [[TMListViewController alloc] initWithTitle:@"Trang chủ" firstPage:first];
        _list.willRefresh = ^{ [weakSelf markFresh]; };
        _grid = [[TMGridViewController alloc] initWithFirstPage:first];
        _gridMode = [[NSUserDefaults standardUserDefaults] boolForKey:kGridKey];
        [self updateEmptyMessages];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [TMTheme current].background;
    _source = [[UISegmentedControl alloc] initWithItems:@[ @"Đã theo dõi", @"Phổ biến" ]];
    _source.segmentedControlStyle = UISegmentedControlStyleBar;
    _source.selectedSegmentIndex = _subscriptionsSource ? 0 : 1;
    [_source addTarget:self action:@selector(sourcePicked) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _source;
    _mode = [[UISegmentedControl alloc] initWithItems:@[ @"Danh sách", @"Lưới" ]];
    _mode.segmentedControlStyle = UISegmentedControlStyleBar;
    _mode.selectedSegmentIndex = _gridMode ? 1 : 0;
    [_mode addTarget:self action:@selector(modePicked) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_mode];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(subscriptionsChanged)
                                                 name:TMSubscriptionsDidChangeNotification
                                               object:nil];
    [self showChild];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)themeChanged {
    self.view.backgroundColor = [TMTheme current].background;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
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

- (void)updateEmptyMessages {
    NSString *empty = _subscriptionsSource ? @"Chưa có video từ kênh đã theo dõi.\nMở một kênh (từ Tìm kiếm hoặc trang video) rồi "
                                             @"bấm “+ Theo dõi”: video mới của kênh sẽ hiện ở đây."
                                           : @"Máy chủ chưa có video phổ biến.";
    _list.emptyMessage = empty;
    _grid.emptyMessage = empty;
}

- (void)setSubscriptionsSource:(BOOL)subscriptions {
    _subscriptionsSource = subscriptions;
    _source.selectedSegmentIndex = subscriptions ? 0 : 1;
    [[NSUserDefaults standardUserDefaults] setBool:subscriptions forKey:kSourceKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateEmptyMessages];
    [self reloadActiveMarkingOtherStale];
}

- (void)sourcePicked {
    [self setSubscriptionsSource:_source.selectedSegmentIndex == 0];
}

/// A channel was (un)subscribed: the subscriptions feed is out of date.
- (void)subscriptionsChanged {
    if (!_subscriptionsSource) return;
    if (self.isViewLoaded && self.view.window) {
        [self reloadActiveMarkingOtherStale];
    } else {
        _listStale = _gridStale = YES;
    }
}

- (void)reloadActiveMarkingOtherStale {
    if (_gridMode) {
        [_grid reload];
        _listStale = YES;
    } else {
        [_list reload];
        _gridStale = YES;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadIfStale];
}

- (void)reloadIfStale {
    if (_gridMode && _gridStale) {
        _gridStale = NO;
        [_grid reload];
    } else if (!_gridMode && _listStale) {
        _listStale = NO;
        [_list reload];
    }
}

#pragma mark - List / grid

- (UIViewController *)activeChild {
    return _gridMode ? _grid : _list;
}

- (void)showChild {
    UIViewController *show = [self activeChild], *hide = _gridMode ? (UIViewController *)_list : (UIViewController *)_grid;
    if (hide.parentViewController) {
        [hide willMoveToParentViewController:nil];
        [hide.view removeFromSuperview];
        [hide removeFromParentViewController];
    }
    if (show.parentViewController != self) {
        [self addChildViewController:show];
        show.view.frame = self.view.bounds;
        show.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:show.view];
        [show didMoveToParentViewController:self];
    }
    [self reloadIfStale];
}

- (void)setGridMode:(BOOL)grid {
    _gridMode = grid;
    _mode.selectedSegmentIndex = grid ? 1 : 0;
    [[NSUserDefaults standardUserDefaults] setBool:grid forKey:kGridKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self showChild];
}

- (void)modePicked {
    [self setGridMode:_mode.selectedSegmentIndex == 1];
}

- (void)refresh {
    [self markFresh];
    if (_gridMode) {
        [_grid reload];
    } else {
        [_list reload];
    }
}

@end
