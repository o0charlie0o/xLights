# Makefile for standalone xLights native macOS UI testing
#
# This builds a minimal test app to demonstrate the Phase 1A
# window infrastructure without requiring the full xLights build.
#
# Usage:
#   make        - Build the test app
#   make run    - Build and run the test app
#   make clean  - Clean build artifacts

APP_NAME = xLightsNative
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

# Compiler flags
CC = clang
CXX = clang++
OBJC_FLAGS = -fobjc-arc -fmodules
CXXFLAGS = -std=c++17 -stdlib=libc++
FRAMEWORKS = -framework Cocoa -framework Metal -framework QuartzCore
WARNINGS = -Wall -Wextra

# Source files
OBJC_SOURCES = \
	XLAppDelegate.m \
	XLSetupViewController.m \
	XLLayoutViewController.m \
	XLSequencerViewController.m \
	XLInspectorViewController.m

OBJCXX_SOURCES = \
	XLMainWindowController.mm \
	XLEngineBridge.mm \
	main.m

OBJECTS = $(addprefix $(BUILD_DIR)/, $(OBJC_SOURCES:.m=.o) $(OBJCXX_SOURCES:.mm=.o))

# Stub engine headers (for standalone build without full xLights)
STUB_HEADERS = \
	$(BUILD_DIR)/engine/SequenceEngine.h \
	$(BUILD_DIR)/engine/ModelEngine.h \
	$(BUILD_DIR)/engine/OutputEngine.h \
	$(BUILD_DIR)/engine/RenderEngine.h \
	$(BUILD_DIR)/engine/EffectEngine.h

.PHONY: all clean run app bundle

all: app

# Create stub engine headers for standalone testing
$(BUILD_DIR)/engine/%.h:
	@mkdir -p $(dir $@)
	@echo "// Stub header for standalone testing" > $@
	@echo "#pragma once" >> $@
	@echo "namespace xlEngine { }" >> $@

# Build object files
$(BUILD_DIR)/%.o: %.m $(STUB_HEADERS)
	@mkdir -p $(dir $@)
	$(CC) $(OBJC_FLAGS) $(WARNINGS) -I$(BUILD_DIR) -c $< -o $@

$(BUILD_DIR)/%.o: %.mm $(STUB_HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(OBJC_FLAGS) $(CXXFLAGS) $(WARNINGS) -I$(BUILD_DIR) -c $< -o $@

# Link the app
$(MACOS)/$(APP_NAME): $(OBJECTS) | bundle
	$(CXX) $(OBJECTS) $(FRAMEWORKS) -o $@

# Create app bundle structure
bundle:
	@mkdir -p $(MACOS)
	@mkdir -p $(RESOURCES)
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(CONTENTS)/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(CONTENTS)/Info.plist
	@echo '<plist version="1.0">' >> $(CONTENTS)/Info.plist
	@echo '<dict>' >> $(CONTENTS)/Info.plist
	@echo '  <key>CFBundleExecutable</key><string>$(APP_NAME)</string>' >> $(CONTENTS)/Info.plist
	@echo '  <key>CFBundleIdentifier</key><string>org.xlights.native</string>' >> $(CONTENTS)/Info.plist
	@echo '  <key>CFBundleName</key><string>$(APP_NAME)</string>' >> $(CONTENTS)/Info.plist
	@echo '  <key>CFBundlePackageType</key><string>APPL</string>' >> $(CONTENTS)/Info.plist
	@echo '  <key>CFBundleShortVersionString</key><string>1.0</string>' >> $(CONTENTS)/Info.plist
	@echo '  <key>CFBundleVersion</key><string>1</string>' >> $(CONTENTS)/Info.plist
	@echo '  <key>LSMinimumSystemVersion</key><string>10.15</string>' >> $(CONTENTS)/Info.plist
	@echo '  <key>NSPrincipalClass</key><string>NSApplication</string>' >> $(CONTENTS)/Info.plist
	@echo '  <key>NSHighResolutionCapable</key><true/>' >> $(CONTENTS)/Info.plist
	@echo '</dict>' >> $(CONTENTS)/Info.plist
	@echo '</plist>' >> $(CONTENTS)/Info.plist

# Build the app
app: $(MACOS)/$(APP_NAME)
	@echo "Built $(APP_BUNDLE)"

# Run the app
run: app
	@open $(APP_BUNDLE)

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

# Debug: show variables
debug:
	@echo "APP_NAME: $(APP_NAME)"
	@echo "BUILD_DIR: $(BUILD_DIR)"
	@echo "OBJECTS: $(OBJECTS)"
	@echo "STUB_HEADERS: $(STUB_HEADERS)"
