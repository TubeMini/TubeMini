#import "TMListViewController.h"
#import "TMAudioBar.h"
#import "TMAudioPlayer.h"
#import "TMCells.h"
#import "TMChannelViewController.h"
#import "TMTheme.h"
#import "TMVideoViewController.h"

static NSString *const kVideoCell = @"video", *const kChannelCell = @"channel", *const kCommentCell = @"comment";

@implementation TMListViewController {
    NSMutableArray *_items;
    NSString *_next;
    BOOL _loading, _ended;
    NSInteger _generation;
    TMListFooter *_footer;
}

- (instancetype)initWithTitle:(NSString *)title firstPage:(TMFirstPageBlock)firstPage {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = title;
        _firstPage = [firstPage copy];
        _items = [NSMutableArray array];
        _emptyMessage = @"Không có gì ở đây.";
        _deleteTitle = @"Xoá";
    }
    return self;
}

- (NSArray *)items {
    return _items;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[TMVideoCell class] forCellReuseIdentifier:kVideoCell];
    [self.tableView registerClass:[TMChannelCell class] forCellReuseIdentifier:kChannelCell];
    [self.tableView registerClass:[TMCommentCell class] forCellReuseIdentifier:kCommentCell];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(pulled) forControlEvents:UIControlEventValueChanged];
    _footer = [[TMListFooter alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 70)];
    __weak TMListViewController *weakSelf = self;
    _footer.onTap = ^{ [weakSelf retry]; };
    self.tableView.tableFooterView = _footer;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioChanged)
                                                 name:TMAudioPlayerDidChangeNotification
                                               object:nil];
    [self audioChanged];
    [self applyTheme];
    if (self.firstPage) [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    [[TMTheme current] styleTableView:self.tableView];
    self.refreshControl.tintColor = [TMTheme current].secondaryText;
    [_footer applyTheme];
}

- (void)themeChanged {
    [self applyTheme];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // An empty list after an error (e.g. the server address was missing): try again when shown
    if (!_items.count && !_loading && self.firstPage) [self reload];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - Loading

- (void)pulled {
    if (self.willRefresh) self.willRefresh();
    [self reload];
}

- (void)showIdleMessage:(NSString *)message {
    _generation++;
    [_items removeAllObjects];
    _next = nil;
    _loading = NO;
    [self.tableView reloadData];
    [_footer showMessage:message];
}

- (void)reload {
    if (!self.firstPage) {
        [self.refreshControl endRefreshing];
        return;
    }
    NSInteger gen = ++_generation;
    _loading = YES;
    _ended = NO;
    _next = nil;
    [_footer showLoading];
    self.firstPage(^(TMFeed *feed, NSString *error) {
        if (gen != self->_generation) return;
        [self.refreshControl endRefreshing];
        [self->_items removeAllObjects];
        [self handleFeed:feed error:error];
        [self.tableView reloadData];
    });
}

- (void)loadMore {
    if (_loading || !_next.length) return;
    NSInteger gen = _generation;
    _loading = YES;
    [_footer showLoading];
    [[TMAPIClient shared] feedAtURL:_next
                         completion:^(TMFeed *feed, NSString *error) {
                             if (gen != self->_generation) return;
                             NSUInteger before = self->_items.count;
                             [self handleFeed:feed error:error];
                             NSMutableArray *paths = [NSMutableArray array];
                             for (NSUInteger i = before; i < self->_items.count; i++) {
                                 [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
                             }
                             if (paths.count) {
                                 [self.tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
                             }
                         }];
}

- (void)handleFeed:(TMFeed *)feed error:(NSString *)error {
    _loading = NO;
    if (error) {
        [_footer showMessage:[NSString stringWithFormat:@"%@\nChạm để thử lại.", error]];
        return;
    }
    [_items addObjectsFromArray:feed.entries];
    // A next link that brings nothing new would loop forever: stop there
    _next = feed.entries.count ? feed.nextURL : nil;
    _ended = _next.length == 0;
    if (_ended) [_footer showMessage:_items.count ? @"" : self.emptyMessage];
}

- (void)retry {
    if (_items.count && _next.length) {
        [self loadMore];
    } else {
        [self reload];
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    id item = _items[(NSUInteger)indexPath.row];
    if ([item isKindOfClass:[TMChannel class]]) return [TMChannelCell height];
    if ([item isKindOfClass:[TMComment class]]) return [TMCommentCell heightForComment:item width:tableView.bounds.size.width];
    return [TMVideoCell height];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id item = _items[(NSUInteger)indexPath.row];
    if ([item isKindOfClass:[TMChannel class]]) {
        TMChannelCell *cell = [tableView dequeueReusableCellWithIdentifier:kChannelCell forIndexPath:indexPath];
        [cell configureWithChannel:item];
        return cell;
    }
    if ([item isKindOfClass:[TMComment class]]) {
        TMCommentCell *cell = [tableView dequeueReusableCellWithIdentifier:kCommentCell forIndexPath:indexPath];
        [cell configureWithComment:item];
        return cell;
    }
    TMVideoCell *cell = [tableView dequeueReusableCellWithIdentifier:kVideoCell forIndexPath:indexPath];
    if ([item isKindOfClass:[TMVideo class]]) [cell configureWithVideo:item];
    if ([item isKindOfClass:[TMPlaylist class]]) [cell configureWithPlaylist:item];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.onDelete != nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.deleteTitle;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) [self deleteRow:indexPath.row];
}

- (void)deleteRow:(NSInteger)row {
    if (!self.onDelete || row < 0 || row >= (NSInteger)_items.count) return;
    id item = _items[(NSUInteger)row];
    [_items removeObjectAtIndex:(NSUInteger)row];
    [self.tableView deleteRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:row inSection:0] ]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
    if (!_items.count && _ended) [_footer showMessage:self.emptyMessage];
    self.onDelete(item);
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)_items.count - 4) [self loadMore];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self selectRow:indexPath.row];
}

- (void)selectRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_items.count) return;
    id item = _items[(NSUInteger)row];
    if ([item isKindOfClass:[TMVideo class]]) {
        [self.navigationController pushViewController:[[TMVideoViewController alloc] initWithVideo:item] animated:YES];
    } else if ([item isKindOfClass:[TMChannel class]]) {
        [self.navigationController pushViewController:[[TMChannelViewController alloc] initWithChannel:item] animated:YES];
    } else if ([item isKindOfClass:[TMPlaylist class]]) {
        NSString *pid = [item playlistID];
        TMListViewController *videos =
            [[TMListViewController alloc] initWithTitle:[item title]
                                              firstPage:^(TMFeedBlock done) { [[TMAPIClient shared] playlistVideos:pid completion:done]; }];
        videos.emptyMessage = @"Playlist trống.";
        [self.navigationController pushViewController:videos animated:YES];
    }
}

/// Room for the "Chỉ nghe" bar under the last rows.
- (void)audioChanged {
    [TMAudioBar applyInsetTo:self.tableView];
}

@end
