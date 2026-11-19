#import "TMListViewController.h"
#import "TMAudioBar.h"
#import "TMAudioPlayer.h"
#import "TMCells.h"
#import "TMChannelViewController.h"
#import "TMGlass.h"
#import "TMTheme.h"
#import "TMVideoViewController.h"

static NSString *const kVideoCell = @"video", *const kChannelCell = @"channel", *const kCommentCell = @"comment",
                       *const kCardRow = @"cards";

@implementation TMListViewController {
    NSMutableArray *_items;
    NSArray *_videos; // card mode: the videos of _items
    NSString *_next;
    BOOL _loading, _ended;
    NSInteger _generation;
    TMListFooter *_footer;
    TMRefreshControl *_refresh;
    CGFloat _laidOutWidth;
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
    _refresh = [[TMRefreshControl alloc] initWithScrollView:self.tableView];
    __weak TMListViewController *weakSelf = self;
    _refresh.onRefresh = ^{ [weakSelf pulled]; };
    _footer = [[TMListFooter alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 80)];
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
    [_footer applyTheme];
    [_refresh applyTheme];
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

/// Card rows depend on the width (columns): rebuild them when it changes (rotation).
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGFloat W = self.tableView.bounds.size.width;
    if (W == _laidOutWidth) return;
    BOOL first = _laidOutWidth == 0;
    _laidOutWidth = W;
    if (_cards && !first) [self.tableView reloadData];
}

- (void)setCards:(BOOL)cards {
    if (cards == _cards) return;
    _cards = cards;
    [self rebuildVideos];
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (void)rebuildVideos {
    NSMutableArray *v = [NSMutableArray array];
    for (id e in _items) {
        if ([e isKindOfClass:[TMVideo class]]) [v addObject:e];
    }
    _videos = v;
}

#pragma mark - Loading

- (void)pulled {
    if (self.willRefresh) self.willRefresh();
    [self reload];
}

- (void)showIdleMessage:(NSString *)message {
    _generation++;
    [_items removeAllObjects];
    [self rebuildVideos];
    _next = nil;
    _loading = NO;
    [self.tableView reloadData];
    [_footer showMessage:message];
}

- (void)reload {
    if (!self.firstPage) {
        [_refresh endRefreshing];
        return;
    }
    NSInteger gen = ++_generation;
    _loading = YES;
    _ended = NO;
    _next = nil;
    [_footer showLoading];
    self.firstPage(^(TMFeed *feed, NSString *error) {
        if (gen != self->_generation) return;
        [self->_refresh endRefreshing];
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
                             if (self->_cards) {
                                 [self.tableView reloadData]; // the last row may fill up
                                 return;
                             }
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
        [self rebuildVideos];
        [_footer showMessage:[NSString stringWithFormat:@"%@\nChạm để thử lại.", error]];
        return;
    }
    [_items addObjectsFromArray:feed.entries];
    [self rebuildVideos];
    // A next link that brings nothing new would loop forever: stop there
    _next = feed.entries.count ? feed.nextURL : nil;
    _ended = _next.length == 0;
    BOOL empty = _cards ? _videos.count == 0 : _items.count == 0;
    if (_ended) [_footer showMessage:empty ? self.emptyMessage : @""];
}

- (void)retry {
    if (_items.count && _next.length) {
        [self loadMore];
    } else {
        [self reload];
    }
}

#pragma mark - Table

- (NSInteger)columns {
    return [TMVideoCardRow columnsForWidth:self.tableView.bounds.size.width];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (_cards) {
        NSInteger cols = [self columns];
        return ((NSInteger)_videos.count + cols - 1) / cols;
    }
    return (NSInteger)_items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_cards) return [TMVideoCardRow heightForWidth:tableView.bounds.size.width];
    id item = _items[(NSUInteger)indexPath.row];
    if ([item isKindOfClass:[TMChannel class]]) return [TMChannelCell height];
    if ([item isKindOfClass:[TMComment class]]) return [TMCommentCell heightForComment:item width:tableView.bounds.size.width];
    return [TMVideoCell height];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_cards) {
        TMVideoCardRow *row = [tableView dequeueReusableCellWithIdentifier:kCardRow];
        if (!row) row = [[TMVideoCardRow alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCardRow];
        NSInteger cols = [self columns], first = indexPath.row * cols;
        NSRange r = NSMakeRange((NSUInteger)first, (NSUInteger)MIN(cols, (NSInteger)_videos.count - first));
        __weak TMListViewController *weakSelf = self;
        row.onTap = ^(NSInteger index) { [weakSelf openVideoAt:index]; };
        [row configureWithVideos:[_videos subarrayWithRange:r] first:first width:tableView.bounds.size.width];
        return row;
    }
    id item = _items[(NSUInteger)indexPath.row];
    if ([item isKindOfClass:[TMChannel class]]) {
        TMChannelCell *cell = [tableView dequeueReusableCellWithIdentifier:kChannelCell];
        if (!cell) cell = [[TMChannelCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kChannelCell];
        [cell configureWithChannel:item];
        return cell;
    }
    if ([item isKindOfClass:[TMComment class]]) {
        TMCommentCell *cell = [tableView dequeueReusableCellWithIdentifier:kCommentCell];
        if (!cell) cell = [[TMCommentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCommentCell];
        [cell configureWithComment:item];
        return cell;
    }
    TMVideoCell *cell = [tableView dequeueReusableCellWithIdentifier:kVideoCell];
    if (!cell) cell = [[TMVideoCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kVideoCell];
    if ([item isKindOfClass:[TMVideo class]]) [cell configureWithVideo:item];
    if ([item isKindOfClass:[TMPlaylist class]]) [cell configureWithPlaylist:item];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.onDelete != nil && !_cards;
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
    if (!self.onDelete || _cards || row < 0 || row >= (NSInteger)_items.count) return;
    id item = _items[(NSUInteger)row];
    [_items removeObjectAtIndex:(NSUInteger)row];
    [self rebuildVideos];
    [self.tableView deleteRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:row inSection:0] ]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
    if (!_items.count && _ended) [_footer showMessage:self.emptyMessage];
    self.onDelete(item);
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger rows = [self tableView:tableView numberOfRowsInSection:0];
    if (indexPath.row >= rows - (_cards ? 2 : 4)) [self loadMore];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!_cards) [self selectRow:indexPath.row];
}

- (void)selectRow:(NSInteger)row {
    if (_cards) {
        [self openVideoAt:row];
        return;
    }
    if (row < 0 || row >= (NSInteger)_items.count) return;
    [self open:_items[(NSUInteger)row]];
}

- (void)openVideoAt:(NSInteger)index {
    if (index >= 0 && index < (NSInteger)_videos.count) [self open:_videos[(NSUInteger)index]];
}

- (void)open:(id)item {
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

#pragma mark - Scrolling

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [_refresh scrollViewDidScroll];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    [_refresh scrollViewDidEndDragging];
}

/// Room for the floating tab bar (and the "Chỉ nghe" bar) under the last rows.
- (void)audioChanged {
    [TMAudioBar applyInsetTo:self.tableView];
}

@end
