#import <UIKit/UIKit.h>

/// Loads thumbnails / avatars straight from Google (HTTPS) with a two-level cache:
/// a bounded NSCache in RAM (cleared on memory warnings) and `Library/Caches/TMImages` on disk.
/// Images are decoded off the main thread at display size. Cell reuse is safe: each image view
/// remembers the URL it wants, and late results for an old URL are dropped.
@interface TMImageLoader : NSObject
+ (instancetype)shared;
/// Shows `placeholder` now and the image when ready; `size` (points) bounds the decoded image.
- (void)setImageURL:(NSURL *)url onImageView:(UIImageView *)view placeholder:(UIImage *)placeholder size:(CGSize)size;
/// Plain grey placeholder of the given size.
+ (UIImage *)placeholderOfSize:(CGSize)size;
- (void)clearMemory;
@end
