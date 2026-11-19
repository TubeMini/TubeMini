# tmshot — screenshot from SSH on jailbroken iOS 5–8 (dev tool; see main.m; on iOS 8 the picture is black: use TMDebug "shot"). Build: make → .theos/obj/debug/tmshot
TARGET := iphone:clang:9.3:5.0
ARCHS = armv7
include $(THEOS)/makefiles/common.mk
TOOL_NAME = tmshot
tmshot_FILES = main.m
tmshot_FRAMEWORKS = CoreFoundation CoreGraphics ImageIO
tmshot_CODESIGN_FLAGS = -S -Hsha1
include $(THEOS_MAKE_PATH)/tool.mk
