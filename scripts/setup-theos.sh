#!/usr/bin/env bash
# Copied from the ConBangTV_Legacy project (tools/setup-theos.sh, same author) — keeps the same patch marker so a
# shared ~/theos already patched by that project is detected and left alone.
# Cài bộ dựng cho bản iOS 6 trên máy Ubuntu (x86_64): Theos + toolchain iOS của L1ghtmann (clang 11, ld64-609) + SDK iPhoneOS 9.3
# (bản SDK cuối còn armv7) từ theos/sdks, rồi vá SDK cho ld64 mới. Chạy lại nhiều lần không sao (bước đã xong thì bỏ qua).
#   bash scripts/setup-theos.sh          # cài vào ~/theos
set -euo pipefail
THEOS="${THEOS:-$HOME/theos}"
SDK="$THEOS/sdks/iPhoneOS9.3.sdk"

if [[ ! -d "$THEOS/makefiles" ]]; then
    git clone --quiet --recursive --depth 1 https://github.com/theos/theos.git "$THEOS"
fi

if [[ ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ]]; then
    curl -sSL https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-x86_64.tar.xz \
        | tar -xJf - -C "$THEOS/toolchain/"
fi

if [[ ! -d "$SDK" ]]; then
    tmp="$(mktemp -d)"
    git clone --quiet --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git "$tmp/sdks"
    git -C "$tmp/sdks" sparse-checkout set iPhoneOS9.3.sdk
    mv "$tmp/sdks/iPhoneOS9.3.sdk" "$SDK"
    rm -rf "$tmp"
fi

# Vá 1: libSystem.tbd của SDK 9.3 tái xuất /usr/lib/system/liblaunch.dylib nhưng SDK không có liblaunch.tbd — ld64 cũ bỏ qua,
# ld64-609 báo «file not found». App không dùng hàm nào của liblaunch; iOS 6 có sẵn thư viện thật.
if [[ ! -f "$SDK/usr/lib/system/liblaunch.tbd" ]]; then
    cat > "$SDK/usr/lib/system/liblaunch.tbd" <<'EOF'
---
archs:                 [ armv7, armv7s, arm64, i386, x86_64 ]
platform:              ios
install-name:          /usr/lib/system/liblaunch.dylib
current-version:       765.1.8
compatibility-version: 1
exports:
  - archs:              [ armv7, armv7s, arm64, i386, x86_64 ]
    symbols:            [ _launch_msg ]
...
EOF
fi

# Vá 2: libsystem_platform.tbd của bản SDK này thiếu các hàm chuỗi / bộ nhớ (memset, memcpy, bzero…) → «Undefined symbols _memset».
# iOS 7+ để chúng trong libsystem_platform, iOS 6 để trong libsystem_c; app liên kết qua libSystem (tái xuất cả hai) nên khai báo
# ở đây là đủ — lúc chạy dyld tìm trong các thư viện libSystem tái xuất. KHÔNG thêm clock_gettime (iOS 10+, iOS 6 không có).
PLATFORM="$SDK/usr/lib/system/libsystem_platform.tbd"
if ! grep -q "cbtv-legacy-patch" "$PLATFORM"; then
    python3 - "$PLATFORM" <<'EOF'
import sys
path = sys.argv[1]
text = open(path).read()
extra = ("  # cbtv-legacy-patch: hàm chuỗi / bộ nhớ bị thiếu trong bản SDK này\n"
         "  - archs:              [ armv7, armv7s, arm64, i386, x86_64 ]\n"
         "    symbols:            [ _bcmp, _bzero, _memccpy, _memchr, _memcmp, _memcpy, _memmove, _memset,\n"
         "                          _memset_pattern16, _memset_pattern4, _memset_pattern8, _strchr, _strcmp, _strncmp ]\n")
end = text.rstrip().rfind("\n...")
if end < 0:
    sys.exit("không thấy dòng kết thúc «...» trong " + path)
open(path, "w").write(text[:end + 1] + extra + text[end + 1:])
EOF
fi

# Vá 3: iOS 7 chuyển bộ tải URL (NSURLConnection, NSURLRequest, NSHTTPURLResponse, NSURLCredential, NSURLAuthenticationMethod…)
# từ Foundation sang CFNetwork; SDK 9.3 ghi chúng ở CFNetwork nên ld gắn ký hiệu vào CFNetwork → iOS 6 báo «dyld: Symbol not found:
# _NSURLAuthenticationMethodServerTrust … Expected in CFNetwork» (đã gặp trên iPhone 5 iOS 6.1.4). Chuyển mọi ký hiệu NS* của
# CFNetwork.tbd sang Foundation.tbd (trên iOS 6 chúng ở Foundation); hàm C CF* vẫn ở CFNetwork như iOS 6.
FOUNDATION="$SDK/System/Library/Frameworks/Foundation.framework/Foundation.tbd"
CFNETWORK="$SDK/System/Library/Frameworks/CFNetwork.framework/CFNetwork.tbd"
if ! grep -q "cbtv-legacy-patch" "$FOUNDATION"; then
    cp -n "$CFNETWORK" "$CFNETWORK.orig"
    cp -n "$FOUNDATION" "$FOUNDATION.orig"
    python3 - "$CFNETWORK" "$FOUNDATION" <<'EOF'
import re, sys
cfn_path, fnd_path = sys.argv[1], sys.argv[2]
cfn = open(cfn_path).read()
moved = {"symbols": [], "objc-classes": [], "objc-ivars": []}
pat = re.compile(r"(\n {4})(symbols|objc-classes|objc-ivars):( +)\[(.*?)\]", re.S)

def strip_ns(m):
    key = m.group(2)
    items = [s.strip() for s in m.group(4).split(",") if s.strip()]
    keep = [s for s in items if not s.startswith("_NS")]
    moved[key] += [s for s in items if s.startswith("_NS")]
    if not keep:
        return ""
    return "%s%s:%s[ %s ]" % (m.group(1), key, m.group(3), ", ".join(keep))

cfn = pat.sub(strip_ns, cfn)
if not any(moved.values()):
    sys.exit("không thấy ký hiệu NS* nào trong " + cfn_path)

def flow(key, items):
    pad = " " * 26
    lines, cur = [], []
    for s in items:
        cur.append(s)
        if len(", ".join(cur)) > 90:
            lines.append(", ".join(cur))
            cur = []
    if cur:
        lines.append(", ".join(cur))
    return "    %-20s[ %s ]\n" % (key + ":", (",\n" + pad).join(lines))

extra = ("  # cbtv-legacy-patch: ký hiệu NS* chuyển từ CFNetwork về Foundation như iOS 6\n"
         "  - archs:              [ armv7, armv7s, arm64, i386, x86_64 ]\n")
for key in ("symbols", "objc-classes", "objc-ivars"):
    if moved[key]:
        extra += flow(key, moved[key])
fnd = open(fnd_path).read()
end = fnd.rstrip().rfind("\n...")
if end < 0:
    sys.exit("không thấy dòng kết thúc «...» trong " + fnd_path)
open(fnd_path, "w").write(fnd[:end + 1] + extra + fnd[end + 1:])
open(cfn_path, "w").write(cfn)
print("chuyển sang Foundation: %d symbols, %d objc-classes, %d objc-ivars"
      % (len(moved["symbols"]), len(moved["objc-classes"]), len(moved["objc-ivars"])))
EOF
fi

# Vá 4 (TubeMini, iOS 5): `mảng[i]`, `từđiển[khoá]` gọi objectAtIndexedSubscript: / objectForKeyedSubscript:…, SDK ghi «iOS 6+».
# Toolchain của Apple gắn libarclite để có chúng trên iOS 5; toolchain Linux không có libarclite, nên app tự thêm 4 hàm này lúc chạy
# (ios/TubeMini/Core/TMCompat.m). Ghi lại mốc iOS 5.0 cho 4 hàm đó để -Werror=unguarded-availability không chặn; với app nhắm
# iOS 6 trở lên thì không đổi gì.
HEADERS="$SDK/System/Library/Frameworks/Foundation.framework/Headers"
for h in NSArray.h NSDictionary.h NSOrderedSet.h; do
    sed -i -E 's/((Indexed|Keyed)Subscript:\([^)]*\)(idx|key) NS_AVAILABLE\(10_8, )6_0\)/\15_0)/' "$HEADERS/$h"
done

"$THEOS/toolchain/linux/iphone/bin/clang" --version | head -1
echo "Theos: $THEOS — SDK: $SDK"
