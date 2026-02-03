# Makefile for Metal Timeline Spike
# Build a standalone macOS app bundle

APP_NAME = MetalTimeline
BUNDLE = $(APP_NAME).app
BUILD_DIR = build
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE)
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

# Compiler settings
CXX = clang++
OBJCXX = clang++
CXXFLAGS = -std=c++20 -O2 -Wall -fobjc-arc
FRAMEWORKS = -framework Cocoa -framework Metal -framework MetalKit -framework QuartzCore -framework CoreVideo
LDFLAGS = $(FRAMEWORKS)

# Source files
SOURCES = main.mm AppDelegate.mm MetalTimelineView.mm
METAL_SOURCES = TimelineShaders.metal

OBJECTS = $(addprefix $(BUILD_DIR)/, $(SOURCES:.mm=.o))
METAL_LIB = $(RESOURCES_DIR)/default.metallib

.PHONY: all clean run

all: $(BUNDLE_DIR) $(MACOS_DIR)/$(APP_NAME) $(METAL_LIB) $(CONTENTS_DIR)/Info.plist

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUNDLE_DIR):
	mkdir -p $(MACOS_DIR)
	mkdir -p $(RESOURCES_DIR)

$(BUILD_DIR)/%.o: %.mm | $(BUILD_DIR)
	$(OBJCXX) $(CXXFLAGS) -c $< -o $@

$(MACOS_DIR)/$(APP_NAME): $(OBJECTS) | $(BUNDLE_DIR)
	$(OBJCXX) $(CXXFLAGS) $(LDFLAGS) $(OBJECTS) -o $@

# Compile Metal shaders to metallib
$(BUILD_DIR)/TimelineShaders.air: TimelineShaders.metal | $(BUILD_DIR)
	xcrun -sdk macosx metal -c $< -o $@

$(METAL_LIB): $(BUILD_DIR)/TimelineShaders.air | $(BUNDLE_DIR)
	xcrun -sdk macosx metallib $< -o $@

$(CONTENTS_DIR)/Info.plist: | $(BUNDLE_DIR)
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $@
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $@
	@echo '<plist version="1.0">' >> $@
	@echo '<dict>' >> $@
	@echo '  <key>CFBundleExecutable</key>' >> $@
	@echo '  <string>$(APP_NAME)</string>' >> $@
	@echo '  <key>CFBundleIdentifier</key>' >> $@
	@echo '  <string>org.xlights.spikes.MetalTimeline</string>' >> $@
	@echo '  <key>CFBundleName</key>' >> $@
	@echo '  <string>Metal Timeline Spike</string>' >> $@
	@echo '  <key>CFBundlePackageType</key>' >> $@
	@echo '  <string>APPL</string>' >> $@
	@echo '  <key>CFBundleShortVersionString</key>' >> $@
	@echo '  <string>1.0</string>' >> $@
	@echo '  <key>CFBundleVersion</key>' >> $@
	@echo '  <string>1</string>' >> $@
	@echo '  <key>NSHighResolutionCapable</key>' >> $@
	@echo '  <true/>' >> $@
	@echo '  <key>NSPrincipalClass</key>' >> $@
	@echo '  <string>NSApplication</string>' >> $@
	@echo '</dict>' >> $@
	@echo '</plist>' >> $@

run: all
	open $(BUNDLE_DIR)

clean:
	rm -rf $(BUILD_DIR)
