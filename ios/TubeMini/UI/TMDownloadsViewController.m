#import "TMDownloadsViewController.h"
#import "TMAlert.h"
#import "TMAudioBar.h"
#import "TMCompat.h"
#import "TMIcons.h"
#import "TMNavigationController.h"
#import "TMAudioPlayer.h"
#import "TMCells.h"
#import "TMDownloads.h"
#import "TMLibrary.h"
#import "TMPlayer.h"
#import "TMTheme.h"

static NSString *const kCell = @"download";

@implementation TMDownloadsViewController {
    NSArray *_items;
    UIView *_empty;
    UIImageView *_emptyIcon;
    UILabel *_emptyLabel, *_usage;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Đã tải";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    TMSetLargeTitle(self, @"Đã tải", NO);
    // Empty state: a big icon over the explanation
    _empty = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 230)];
    _empty.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _empty.backgroundColor = [UIColor clearColor];
    _emptyIcon = [[UIImageView alloc] initWithFrame:CGRectMake(floor((_empty.bounds.size.width - 64) / 2), 50, 64, 64)];
    _emptyIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [_empty addSubview:_emptyIcon];
    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, 126, _empty.bounds.size.width - 60, 80)];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = TMAlignCenter;
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.font = TMFontRegular(15);
    _emptyLabel.text = @"Chưa tải video nào.\nMở một video rồi bấm “Tải về” để xem cả khi không có mạng.";
    [_empty addSubview:_emptyLabel];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadsChanged:)
                                                 name:TMDownloadsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioChanged)
                                                 name:TMAudioPlayerDidChangeNotification
                                               object:nil];
    [self audioChanged];
    [self applyTheme];
    [self refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    TMTheme *t = [TMTheme current];
    [t styleTableView:self.tableView];
    _emptyLabel.textColor = t.secondaryText;
    _emptyIcon.image = TMIcon(@"download", 64, t.tertiaryText);
    _usage.textColor = t.secondaryText;
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
        _usage.textAlignment = TMAlignCenter;
        _usage.backgroundColor = [UIColor clearColor];
        _usage.font = TMFontRegular(13);
    }
    _usage.textColor = [TMTheme current].secondaryText;
    [self updateUsage];
    self.tableView.tableFooterView = _items.count ? _usage : _empty;
    [self.tableView reloadData];
}

- (void)updateUsage {
    _usage.text = [NSString stringWithFormat:@"%lu video · %@ trên %@", (unsigned long)_items.count,
                                             [TMDownloads megabytes:[[TMDownloads shared] bytesUsed]], [UIDevice currentDevice].model];
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
    TMVideoCell *cell = [tableView dequeueReusableCellWithIdentifier:kCell];
    if (!cell) cell = [[TMVideoCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCell];
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
        NSString *vid = x.videoID;
        [TMAlert sheetWithTitle:x.title
                        buttons:@[ @"Huỷ tải và xoá" ]
               destructiveIndex:0
                        handler:^(NSInteger i) {
                            if (i == 0) [[TMDownloads shared] remove:vid];
                        }];
    }
    }
}

/// Room for the "Chỉ nghe" bar under the last rows.
- (void)audioChanged {
    [TMAudioBar applyInsetTo:self.tableView];
}

@end
