// tmshot — screenshot of whatever is on screen, from SSH, on a jailbroken iOS 6 device.
//   tmshot /var/mobile/Documents/shot.png
// Uses the private CARenderServerRenderDisplay (QuartzCore) into an IOSurface; both are looked up
// with dlsym at runtime so a missing symbol fails gracefully instead of breaking dyld.
// Falls back to UIGetScreenImage (UIKit). Writes a PNG with ImageIO.
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef void *IOSurfaceRef;

static int writePNG(CGImageRef img, const char *path) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    CFRelease(url);
    if (!dst) return 0;
    CGImageDestinationAddImage(dst, img, NULL);
    int ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    return ok;
}

static void cfnum(CFMutableDictionaryRef d, const char *key, int v) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingASCII);
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &v);
    CFDictionarySetValue(d, k, n);
    CFRelease(k);
    CFRelease(n);
}

static CGImageRef grabRenderServer(int width, int height) {
    void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY);
    void *ios = dlopen("/System/Library/PrivateFrameworks/IOSurface.framework/IOSurface", RTLD_LAZY);
    void (*render)(mach_port_t, CFStringRef, IOSurfaceRef, int, int) = qc ? dlsym(qc, "CARenderServerRenderDisplay") : NULL;
    IOSurfaceRef (*create)(CFDictionaryRef) = ios ? dlsym(ios, "IOSurfaceCreate") : NULL;
    int (*lock)(IOSurfaceRef, uint32_t, uint32_t *) = ios ? dlsym(ios, "IOSurfaceLock") : NULL;
    int (*unlock)(IOSurfaceRef, uint32_t, uint32_t *) = ios ? dlsym(ios, "IOSurfaceUnlock") : NULL;
    void *(*base)(IOSurfaceRef) = ios ? dlsym(ios, "IOSurfaceGetBaseAddress") : NULL;
    size_t (*bpr)(IOSurfaceRef) = ios ? dlsym(ios, "IOSurfaceGetBytesPerRow") : NULL;
    if (!render || !create || !lock || !unlock || !base || !bpr) {
        fprintf(stderr, "render server API not available\n");
        return NULL;
    }
    int rowBytes = width * 4;
    CFMutableDictionaryRef props =
        CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    cfnum(props, "IOSurfaceWidth", width);
    cfnum(props, "IOSurfaceHeight", height);
    cfnum(props, "IOSurfaceBytesPerElement", 4);
    cfnum(props, "IOSurfaceBytesPerRow", rowBytes);
    cfnum(props, "IOSurfaceAllocSize", rowBytes * height);
    cfnum(props, "IOSurfacePixelFormat", 'BGRA');
    CFDictionarySetValue(props, CFSTR("IOSurfaceIsGlobal"), kCFBooleanTrue);
    IOSurfaceRef surface = create(props);
    CFRelease(props);
    if (!surface) return NULL;

    render(0, CFSTR("LCD"), surface, 0, 0);
    lock(surface, 1 /* read-only */, NULL);
    size_t stride = bpr(surface);
    CFDataRef data = CFDataCreate(NULL, base(surface), stride * height);
    unlock(surface, 1, NULL);
    CFRelease(surface);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CFRelease(data);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGImageRef img = CGImageCreate(width, height, 8, 32, stride, cs,
                                   kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, provider, NULL, false,
                                   kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(provider);
    return img;
}

static CGImageRef grabUIKit(void) {
    void *uikit = dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_LAZY);
    CGImageRef (*grab)(void) = uikit ? dlsym(uikit, "UIGetScreenImage") : NULL;
    return grab ? grab() : NULL;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: tmshot <out.png> [width height] | tmshot <out.png> --uikit\n");
        return 2;
    }
    // --uikit: skip the render server (its signature differs on iOS 5 and crashes there)
    int uikitOnly = argc > 2 && strcmp(argv[2], "--uikit") == 0;
    int width = argc > 3 ? atoi(argv[2]) : 768;
    int height = argc > 3 ? atoi(argv[3]) : 1024;
    CGImageRef img = uikitOnly ? NULL : grabRenderServer(width, height);
    const char *how = "render server";
    if (!img) {
        img = grabUIKit();
        how = "UIGetScreenImage";
    }
    if (!img) {
        fprintf(stderr, "no screenshot method worked\n");
        return 1;
    }
    int ok = writePNG(img, argv[1]);
    printf("%s: %zux%zu via %s → %s\n", ok ? "ok" : "write failed", CGImageGetWidth(img), CGImageGetHeight(img), how,
           argv[1]);
    CGImageRelease(img);
    return ok ? 0 : 1;
}
