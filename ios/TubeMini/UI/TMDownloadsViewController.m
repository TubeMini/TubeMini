#import "TMDownloadsViewController.h"
#import "TMCells.h"
#import "TMDownloads.h"
#import "TMLibrary.h"
#import "TMPlayer.h"
#import "TMTheme.h"

static NSString *const kCell = @"download";

@implementation TMDownloadsViewController {
    NSArray *_items;
    UILabel *_empty, *_usage;
    TMDownload *_pending; // the row an action sheet is about
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Đã tải";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[TMVideoCell class] forCellReuseIdentifier:kCell];
    _empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 120)];
    _empty.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _empty.numberOfLines = 0;
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.backgroundColor = [UIColor clearColor];
    _empty.font = [UIFont systemFontOfSize:15];
    _empty.text = @"Chưa tải video nào.\nMở một video rồi bấm “⬇ Tải về” để xem cả khi không có mạng.";
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadsChanged:)
                                                 name:TMDownloadsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [self applyTheme];
    [self refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)applyTheme {
    [[TMTheme current] styleTableView:self.tableView];
    _empty.textColor = [TMTheme current].secondaryText;
    _usage.textColor = [TMTheme current].secondaryText;
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh {
    _items = [TMDownloads shared].items;
    if (!_usage) {
        _usage = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 50)];
        _usage.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _usage.textAlignment = NSTextAlignmentCenter;
        _usage.backgroundColor = [UIColor clearColor];
        _usage.font = [UIFont systemFontOfSize:13];
    }
    _usage.textColor = [TMTheme current].secondaryText;
    [self updateUsage];
    self.tableView.tableFooterView = _items.count ? _usage : _empty;
    [self.tableView reloadData];
}

- (void)updateUsage {
    _usage.text = [NSString stringWithFormat:@"%lu video · %@ trên iPad", (unsigned long)_items.count,
                                             [TMDownloads megabytes:[[TMDownloads shared] bytesUsed]]];
}

/// Progress ticks only repaint their row; adds / removals reload everything.
- (void)downloadsChanged:(NSNotification *)n {
    if (!self.isViewLoaded) return;
    NSString *vid = n.userInfo[@"videoID"];
    NSArray *now = [TMDownloads shared].items;
    if (!vid || now.count != _items.count) {
        [self refresh];
        return;
    }
    NSUInteger row = [_items indexOfObjectPassingTest:^BOOL(TMDownload *x, NSUInteger i, BOOL *stop) {
        return [x.videoID isEqualToString:vid];
    }];
    if (row == NSNotFound) {
        [self refresh];
        return;
    }
    TMVideoCell *cell = (TMVideoCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
    if (cell) [self configure:cell with:_items[row]];
    [self updateUsage];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [TMVideoCell height];
}

- (void)configure:(TMVideoCell *)cell with:(TMDownload *)x {
    NSString *meta = x.statusText;
    if (x.dubbed) meta = [meta stringByAppendingString:@" · tiếng lồng AI"];
    if (x.author.length) meta = [NSString stringWithFormat:@"%@ · %@", x.author, meta];
    CGFloat progress = 0;
    if (x.state == TMDownloadRunning || x.state == TMDownloadWaiting) {
        progress = x.total > 0 ? (CGFloat)x.received / x.total : 0;
    } else if (x.state == TMDownloadDone && x.duration > 0) {
        progress = MIN(1, (CGFloat)x.position / x.duration); // how far it was watched
    }
    [cell configureWithVideo:[x video] meta:meta progress:progress];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TMVideoCell *cell = [tableView dequeueReusableCellWithIdentifier:kCell forIndexPath:indexPath];
    [self configure:cell with:_items[(NSUInteger)indexPath.row]];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Xoá";
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    TMDownload *x = _items[(NSUInteger)indexPath.row];
    [[TMDownloads shared] remove:x.videoID]; // posts the change → refresh
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self selectRow:indexPath.row];
}

- (void)selectRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_items.count) return;
    TMDownload *x = _items[(NSUInteger)row];
    switch (x.state) {
    case TMDownloadDone: {
        NSInteger start = [TMLibrary resumePositionFor:x.position duration:x.duration];
        [[TMPlayer shared] playFile:x.filePath video:[x video] startAt:start from:self];
        break;
    }
    case TMDownloadFailed:
        [[TMDownloads shared] retry:x.videoID];
        break;
    default: {
        _pending = x;
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:x.title
                                                           delegate:self
                                                  cancelButtonTitle:nil
                                             destructiveButtonTitle:@"Huỷ tải và xoá"
                                                  otherButtonTitles:nil];
        CGRect r = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        [sheet showFromRect:r inView:self.tableView animated:YES];
    }
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.destructiveButtonIndex && _pending) [[TMDownloads shared] remove:_pending.videoID];
    _pending = nil;
}

@end
