#import <UIKit/UIKit.h>

/// Loads thumbnails / avatars straight from Google (HTTPS) with a two-level cache:
/// a bounded NSCache in RAM (cleared on memory warnings) and `Library/Caches/TMImages` on disk.
/// Images are decoded off the main thread at display size. Cell reuse is safe: each image view
/// remembers the URL it wants, and late results for an old URL are dropped.
@interface TMImageLoader : NSObject
+ (instancetype)shared;
/// Shows `placeholder` now and the image when ready; `size` (points) bounds the decoded image.
- (void)setImageURL:(NSURL *)url onImageView:(UIImageView *)view placeholder:(UIImage *)placeholder size:(CGSize)size;
/// Same, cropped to fill exactly `size` with rounded corners (transparent), so lists need no
/// cornerRadius masks (offscreen passes the A4 / A5 cannot afford while scrolling). radius = size / 2: a circle.
- (void)setImageURL:(NSURL *)url onImageView:(UIImageView *)view size:(CGSize)size radius:(CGFloat)radius;
- (void)setImageURL:(NSURL *)url onImageView:(UIImageView *)view placeholder:(UIImage *)placeholder size:(CGSize)size radius:(CGFloat)radius;
/// Plain grey placeholder of the given size.
+ (UIImage *)placeholderOfSize:(CGSize)size;
/// Rounded grey placeholder.
+ (UIImage *)placeholderOfSize:(CGSize)size radius:(CGFloat)radius;
- (void)clearMemory;
@end
