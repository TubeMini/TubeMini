#import "TMSearchViewController.h"
#import "TMTheme.h"

@implementation TMSearchViewController {
    UISearchBar *_bar;
}

- (instancetype)init {
    return [super initWithTitle:@"Tìm kiếm" firstPage:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 88)];
    _bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _bar.placeholder = @"Tìm video hoặc kênh";
    _bar.scopeButtonTitles = @[ @"Video", @"Kênh" ];
    _bar.showsScopeBar = YES;
    _bar.delegate = self;
    _bar.autocorrectionType = UITextAutocorrectionTypeNo;
    [_bar sizeToFit];
    self.tableView.tableHeaderView = _bar;
    [self applyTheme];
    [self showIdleMessage:@"Nhập từ khoá rồi bấm Tìm."];
}

- (void)applyTheme {
    [super applyTheme];
    TMTheme *t = [TMTheme current];
    _bar.tintColor = t.dark ? [UIColor colorWithWhite:0.16 alpha:1] : [UIColor colorWithRed:0.75 green:0.24 blue:0.24 alpha:1];
    // UISearchBar.keyboardAppearance is iOS 7+ (crashes on iOS 6): set it on the inner text field
    for (UIView *v in _bar.subviews) {
        if ([v isKindOfClass:[UITextField class]]) ((UITextField *)v).keyboardAppearance = t.keyboard;
    }
}

// iOS 6 has no keyboardDismissMode: hide the keyboard when the list starts scrolling
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [_bar resignFirstResponder];
}

- (void)runSearch:(NSString *)query scope:(NSInteger)scope {
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _bar.text = q;
    _bar.selectedScopeButtonIndex = scope;
    [_bar resignFirstResponder];
    if (!q.length) return;
    BOOL channels = scope == 1;
    self.emptyMessage = channels ? @"Không tìm thấy kênh nào." : @"Không tìm thấy video nào.";
    self.firstPage = ^(TMFeedBlock done) {
        if (channels) {
            [[TMAPIClient shared] searchChannels:q completion:done];
        } else {
            [[TMAPIClient shared] searchVideos:q completion:done];
        }
    };
    [self reload];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self runSearch:searchBar.text scope:searchBar.selectedScopeButtonIndex];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    if (searchBar.text.length) [self runSearch:searchBar.text scope:selectedScope];
}

@end
