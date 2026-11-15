#import "TMHelloViewController.h"
#import "TMLog.h"

@implementation TMHelloViewController

- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    root.backgroundColor = [UIColor whiteColor];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    CGFloat w = root.bounds.size.width;
    CGFloat midY = root.bounds.size.height / 2;
    UIViewAutoresizing centered = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin |
                                  UIViewAutoresizingFlexibleBottomMargin;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, midY - 70, w - 40, 60)];
    title.text = @"Xin chào TubeMini";
    title.font = [UIFont boldSystemFontOfSize:44];
    title.textAlignment = NSTextAlignmentCenter;
    title.backgroundColor = [UIColor clearColor];
    title.autoresizingMask = centered;
    [root addSubview:title];

    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, midY, w - 40, 60)];
    sub.text = [NSString stringWithFormat:@"Phiên bản %@ · iOS %@ · %@\nGiai đoạn 0: dựng khung", info[@"CFBundleShortVersionString"],
                                          [UIDevice currentDevice].systemVersion, TMDeviceModel()];
    sub.numberOfLines = 2;
    sub.font = [UIFont systemFontOfSize:20];
    sub.textColor = [UIColor darkGrayColor];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.backgroundColor = [UIColor clearColor];
    sub.autoresizingMask = centered;
    [root addSubview:sub];

    self.view = root;
    self.title = @"TubeMini";
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

@end
