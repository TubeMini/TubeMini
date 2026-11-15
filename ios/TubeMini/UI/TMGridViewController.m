#import "TMGridViewController.h"
#import "TMAudioBar.h"
#import "TMAudioPlayer.h"
#import "TMCells.h"
#import "TMFormat.h"
#import "TMImageLoader.h"
#import "TMTheme.h"
#import "TMVideoViewController.h"

static NSString *const kTile = @"tile", *const kFooter = @"footer";
static const CGFloat kGap = 14, kTextH = 74;

#pragma mark - Tile

@interface TMVideoGridCell : UICollectionViewCell
- (void)configureWithVideo:(TMVideo *)video;
@end

@implementation TMVideoGridCell {
    UIImageView *_thumb;
    UILabel *_duration, *_title, *_meta;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _thumb = [[UIImageView alloc] init];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        [self.contentView addSubview:_thumb];
        _duration = [[UILabel alloc] init];
        _duration.font = [UIFont boldSystemFontOfSize:12];
        _duration.textColor = [UIColor whiteColor];
        _duration.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
        _duration.textAlignment = NSTextAlignmentCenter;
        [_thumb addSubview:_duration];
        _title = [[UILabel alloc] init];
        _title.font = [UIFont boldSystemFontOfSize:15];
        _title.numberOfLines = 2;
        _title.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_title];
        _meta = [[UILabel alloc] init];
        _meta.font = [UIFont systemFontOfSize:12];
        _meta.numberOfLines = 2;
        _meta.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_meta];
        self.selectedBackgroundView = [[UIView alloc] init];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, th = floor(w * 9 / 16);
    _thumb.frame = CGRectMake(0, 0, w, th);
    CGSize d = [_duration.text sizeWithFont:_duration.font];
    _duration.hidden = _duration.text.length == 0;
    _duration.frame = CGRectMake(w - d.width - 12, th - 22, d.width + 8, 17);
    CGSize ts = [_title.text sizeWithFont:_title.font constrainedToSize:CGSizeMake(w, 38) lineBreakMode:NSLineBreakByTruncatingTail];
    _title.frame = CGRectMake(0, th + 6, w, ts.height);
    CGSize ms = [_meta.text sizeWithFont:_meta.font constrainedToSize:CGSizeMake(w, 30) lineBreakMode:NSLineBreakByTruncatingTail];
    _meta.frame = CGRectMake(0, th + 8 + ts.height, w, ms.height);
}

- (void)configureWithVideo:(TMVideo *)v {
    TMTheme *t = [TMTheme current];
    self.backgroundColor = t.background;
    self.contentView.backgroundColor = t.background;
    self.selectedBackgroundView.backgroundColor = t.selection;
    _title.textColor = t.text;
    _meta.textColor = t.secondaryText;
    _title.text = v.title;
    _meta.text = [TMFormat join:@[ v.author ?: @"", [TMFormat views:v.views], [TMFormat relativeDate:v.published] ]];
    _duration.text = [TMFormat duration:v.duration];
    CGSize size = CGSizeMake(320, 180);
    [[TMImageLoader shared] setImageURL:v.thumbnailURL
                            onImageView:_thumb
                            placeholder:[TMImageLoader placeholderOfSize:size]
                                   size:size];
    [self setNeedsLayout];
}

@end

#pragma mark - Footer

@interface TMGridFooter : UICollectionReusableView
@property (nonatomic, readonly) TMListFooter *footer;
@end

@implementation TMGridFooter
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _footer = [[TMListFooter alloc] initWithFrame:self.bounds];
        _footer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_footer];
    }
    return self;
}
@end

#pragma mark - Controller

@implementation TMGridViewController {
    TMFirstPageBlock _firstPage;
    NSMutableArray *_items;
    NSString *_next;
    BOOL _loading;
    NSInteger _generation;
    NSString *_footerMessage; // nil = spinner
    CGFloat _laidOutWidth;
}

- (instancetype)initWithFirstPage:(TMFirstPageBlock)firstPage {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = kGap;
    layout.minimumLineSpacing = kGap + 4;
    layout.sectionInset = UIEdgeInsetsMake(kGap, kGap, kGap, kGap);
    layout.footerReferenceSize = CGSizeMake(100, 70);
    if ((self = [super initWithCollectionViewLayout:layout])) {
        _firstPage = [firstPage copy];
        _items = [NSMutableArray array];
        _emptyMessage = @"Không có gì ở đây.";
    }
    return self;
}

- (NSArray *)items {
    return _items;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[TMVideoGridCell class] forCellWithReuseIdentifier:kTile];
    [self.collectionView registerClass:[TMGridFooter class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                   withReuseIdentifier:kFooter];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged)
                                                 name:TMThemeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioChanged)
                                                 name:TMAudioPlayerDidChangeNotification
                                               object:nil];
    [self audioChanged];
    self.collectionView.backgroundColor = [TMTheme current].background;
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!_items.count && !_loading) [self reload];
}

- (void)themeChanged {
    self.collectionView.backgroundColor = [TMTheme current].background;
    [self.collectionView reloadData];
}

/// Tile size for the current width: 3 columns up to ~800 pt (iPad portrait), 4 beyond.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGFloat W = self.collectionView.bounds.size.width;
    if (W == _laidOutWidth || W <= 0) return;
    _laidOutWidth = W;
    NSInteger cols = W > 800 ? 4 : (W > 500 ? 3 : 2);
    CGFloat w = floor((W - kGap * (cols + 1)) / cols);
    // UICollectionViewController.collectionViewLayout is iOS 7+: go through the collection view (iOS 6)
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    layout.itemSize = CGSizeMake(w, floor(w * 9 / 16) + kTextH);
    [layout invalidateLayout];
}

#pragma mark - Loading

- (void)reload {
    if (!_firstPage) return;
    NSInteger gen = ++_generation;
    _loading = YES;
    _next = nil;
    _footerMessage = nil;
    [self.collectionView reloadData];
    _firstPage(^(TMFeed *feed, NSString *error) {
        if (gen != self->_generation) return;
        [self->_items removeAllObjects];
        [self handleFeed:feed error:error];
        [self.collectionView reloadData];
    });
}

- (void)loadMore {
    if (_loading || !_next.length) return;
    NSInteger gen = _generation;
    _loading = YES;
    _footerMessage = nil;
    [[TMAPIClient shared] feedAtURL:_next
                         completion:^(TMFeed *feed, NSString *error) {
                             if (gen != self->_generation) return;
                             [self handleFeed:feed error:error];
                             [self.collectionView reloadData];
                         }];
}

- (void)handleFeed:(TMFeed *)feed error:(NSString *)error {
    _loading = NO;
    if (error) {
        _footerMessage = [NSString stringWithFormat:@"%@\nChạm để thử lại.", error];
        return;
    }
    for (id e in feed.entries) {
        if ([e isKindOfClass:[TMVideo class]]) [_items addObject:e];
    }
    _next = feed.entries.count ? feed.nextURL : nil;
    _footerMessage = _next.length ? nil : (_items.count ? @"" : self.emptyMessage);
}

- (void)retry {
    if (_items.count && _next.length) {
        [self loadMore];
    } else {
        [self reload];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    // iOS 6 has no willDisplayCell for collection views: load more when near the bottom
    if (sv.contentOffset.y + sv.bounds.size.height > sv.contentSize.height - 600) [self loadMore];
}

#pragma mark - Collection view

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    TMVideoGridCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kTile forIndexPath:indexPath];
    [cell configureWithVideo:_items[(NSUInteger)indexPath.item]];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    TMGridFooter *f = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:kFooter forIndexPath:indexPath];
    __weak TMGridViewController *weakSelf = self;
    f.footer.onTap = ^{ [weakSelf retry]; };
    if (_footerMessage) {
        [f.footer showMessage:_footerMessage];
    } else {
        [f.footer showLoading];
    }
    return f;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [cv deselectItemAtIndexPath:indexPath animated:YES];
    [self selectItem:indexPath.item];
}

- (void)selectItem:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return;
    [self.navigationController pushViewController:[[TMVideoViewController alloc] initWithVideo:_items[(NSUInteger)index]]
                                         animated:YES];
}

/// Room for the "Chỉ nghe" bar under the last rows.
- (void)audioChanged {
    [TMAudioBar applyInsetTo:self.collectionView];
}

@end
