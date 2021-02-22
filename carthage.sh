# https://github.com/Carthage/Carthage/issues/3019

set -euo pipefail

xcode_config=$(mktemp /tmp/static.xcode_config.XXXXXX)
trap 'rm -f "$xcode_config"' INT TERM HUP EXIT

# For Xcode 12 make sure EXCLUDED_ARCHS is set to arm architectures otherwise
# the build will fail on lipo due to duplicate architectures.

XCODE_VERSION=$(xcodebuild -version | grep "Build version" | cut -d' ' -f3)
echo "EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_simulator__NATIVE_ARCH_64_BIT_x86_64__XCODE_1200__BUILD_$XCODE_VERSION = arm64 arm64e armv7 armv7s armv6 armv8" >> $xcode_config

echo 'EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_simulator__NATIVE_ARCH_64_BIT_x86_64__XCODE_1200 = $(EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_simulator__NATIVE_ARCH_64_BIT_x86_64__XCODE_1200__BUILD_$(XCODE_PRODUCT_BUILD_VERSION))' >> $xcode_config
echo 'EXCLUDED_ARCHS = $(inherited) $(EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_$(EFFECTIVE_PLATFORM_SUFFIX)__NATIVE_ARCH_64_BIT_$(NATIVE_ARCH_64_BIT)__XCODE_$(XCODE_VERSION_MAJOR))' >> $xcode_config

export XCODE_xcode_config_FILE="$xcode_config"
carthage "$@"
