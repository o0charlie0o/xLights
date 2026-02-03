APP_NAME = AppKitInspector
BUILD_DIR = build

SOURCES = main.m \
          AppDelegate.m \
          InspectorView.m \
          InspectorDisclosureGroup.m \
          InspectorPropertyRow.m \
          InspectorProperty.m \
          InspectorGroup.m

OBJECTS = $(SOURCES:%.m=$(BUILD_DIR)/%.o)

CC = clang
CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
         -mmacosx-version-min=13.0 -std=gnu17
LDFLAGS = -framework Cocoa -framework UniformTypeIdentifiers

all: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/%.o: %.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

run: all
	$(BUILD_DIR)/$(APP_NAME)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run clean
