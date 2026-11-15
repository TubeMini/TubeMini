# TubeMini — YouTube client for iPad on iOS 6 (jailbroken). Theos on Linux, SDK 9.3 (patched for iOS 6), armv7 only.
#   make package                    debug build (includes Debug/: command file, screenshots)
#   make package FINALPACKAGE=1     release build
# Toolchain setup: docs/SETUP.md
TARGET := iphone:clang:9.3:6.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = TubeMini

# dpkg on iOS 6 only reads gzip-compressed .deb; the iOS 6 kernel only understands SHA-1 code signatures
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
TARGET_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TubeMini
TubeMini_FILES = main.m $(wildcard Core/*.m) $(wildcard UI/*.m)
TubeMini_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore MediaPlayer AVFoundation
TubeMini_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ICore -IUI -IDebug
ifneq ($(FINALPACKAGE),1)
TubeMini_FILES += $(wildcard Debug/*.m)
TubeMini_CFLAGS += -DTM_DEBUG=1
endif

include $(THEOS_MAKE_PATH)/application.mk

# Files copied from Windows lose the executable bit
before-package::
	chmod 0755 $(THEOS_STAGING_DIR)/DEBIAN/postinst
