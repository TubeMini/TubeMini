#import "TMSearchViewController.h"
#import "TMCells.h"
#import "TMCompat.h"
#import "TMGlass.h"
#import "TMIcons.h"
#import "TMNavigationController.h"
#import "TMTheme.h"

@implementation TMSearchViewController {
    UIView *_header;
    UIImageView *_fieldBack, *_glyph;
    TMTextField *_field;
    TMChipBar *_scopes;
    NSInteger _scope;
}

- (instancetype)init {
    return [super initWithTitle:@"Tìm kiếm" firstPage:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    TMSetLargeTitle(self, @"Tìm kiếm", NO);
    CGFloat W = self.tableView.bounds.size.width, m = TMListMargin();
    _header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 104)];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _header.backgroundColor = [UIColor clearColor];
    _fieldBack = [[UIImageView alloc] initWithFrame:CGRectMake(m, 8, W - 2 * m, 42)];
    _fieldBack.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _fieldBack.userInteractionEnabled = YES;
    [_header addSubview:_fieldBack];
    _glyph = [[UIImageView alloc] initWithFrame:CGRectMake(12, 11, 20, 20)];
    [_fieldBack addSubview:_glyph];
    _field = [[TMTextField alloc] initWithFrame:CGRectMake(40, 0, _fieldBack.bounds.size.width - 48, 42)];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _field.borderStyle = UITextBorderStyleNone;
    _field.font = TMFontRegular(17);
    _field.placeholder = @"Tìm video hoặc kênh";
    _field.returnKeyType = UIReturnKeySearch;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _field.delegate = self;
    [_fieldBack addSubview:_field];
    _scopes = [[TMChipBar alloc] initWithFrame:CGRectMake(0, 56, W, 44)];
    _scopes.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _scopes.titles = @[ @"Video", @"Kênh" ];
    __weak TMSearchViewController *weakSelf = self;
    _scopes.onSelect = ^(NSInteger i) { [weakSelf scopePicked:i]; };
    [_header addSubview:_scopes];
    self.tableView.tableHeaderView = _header;
    [self applyTheme];
    [self showIdleMessage:@"Nhập từ khoá rồi bấm Tìm."];
}

- (void)applyTheme {
    [super applyTheme];
    TMTheme *t = [TMTheme current];
    _fieldBack.image = TMRoundImage(t.elevated, 21);
    _glyph.image = TMIcon(@"search", 20, t.secondaryText);
    _field.textColor = t.text;
    _field.keyboardAppearance = t.keyboard;
    [_field setNeedsDisplay]; // placeholder colour
}

// iOS 5/6 have no keyboardDismissMode: hide the keyboard when the list starts scrolling
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [_field resignFirstResponder];
}

- (void)runSearch:(NSString *)query scope:(NSInteger)scope {
    [self view]; // the field is built in viewDidLoad
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _field.text = q;
    _scope = scope;
    _scopes.selectedIndex = scope;
    [_field resignFirstResponder];
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

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self runSearch:textField.text scope:_scope];
    return YES;
}

- (void)scopePicked:(NSInteger)scope {
    _scope = scope;
    if (_field.text.length) [self runSearch:_field.text scope:scope];
}

@end
