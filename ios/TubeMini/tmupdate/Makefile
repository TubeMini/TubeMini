# tmupdate: setuid-root helper that installs a TubeMini update package and resprings (see main.c).
TARGET := iphone:clang:9.3:6.0
ARCHS = armv7
TARGET_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS)/makefiles/common.mk

TOOL_NAME = tmupdate
tmupdate_FILES = main.c
tmupdate_INSTALL_PATH = /usr/libexec/tubemini

include $(THEOS_MAKE_PATH)/tool.mk
