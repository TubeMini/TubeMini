#import "TMHomeViewController.h"
#import "TMAPIClient.h"
#import "TMGridViewController.h"
#import "TMListViewController.h"
#import "TMTheme.h"

static NSString *const kGridKey = @"TMHomeGrid";

@implementation TMHomeViewController {
    TMListViewController *_list;
    TMGridViewController *_grid;
    UISegmentedControl *_mode;
}

- (instancetype)init {
    if ((self = [super init])) {
        self.title = @"Phổ biến";
        TMFirstPageBlock popular = ^(TMFeedBlock done) { [[TMAPIClient shared] popular:done]; };
        _list = [[TMListViewController alloc] initWithTitle:@"Phổ biến" firstPage:popular];
        _list.emptyMessage = @"Máy chủ chưa có video phổ biến.";
        _grid = [[TMGridViewController alloc] initWithFirstPage:popular];
        _grid.emptyMessage = _list.emptyMessage;
        _gridMode = [[NSUserDefaults standardUserDefaults] boolForKey:kGridKey];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [TMTheme current].background;
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
    if (_gridMode) {
        [_grid reload];
    } else {
        [_list reload];
    }
}

@end
