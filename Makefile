SWIFTC = swiftc
SDK_PATH = $(shell xcrun --show-sdk-path)
SWIFT_FLAGS = -target arm64-apple-macosx14.0 -sdk $(SDK_PATH) -g

SRC_DIR = Sources/MarkdownEditor
TEST_DIR = Tests
BUILD_DIR = build

CORE_SRCS = $(SRC_DIR)/AST.swift $(SRC_DIR)/Parser.swift $(SRC_DIR)/HTMLRenderer.swift
APP_SRCS = $(SRC_DIR)/TraceLog.swift $(SRC_DIR)/DocumentController.swift
EDITOR_SRCS = $(SRC_DIR)/Views/Editor/EditorView.swift
PREVIEW_SRCS = $(SRC_DIR)/Views/Preview/WebPreviewView.swift
SPLIT_SRCS = $(SRC_DIR)/Views/SplitView.swift

FRAMEWORKS = -framework AppKit -framework SwiftUI -framework WebKit

.PHONY: all clean test run

all: $(BUILD_DIR)/test_runner $(BUILD_DIR)/MarkdownEditor

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# For test runner: compile core logic + DocumentController (needs AppKit for NSImage etc)
$(BUILD_DIR)/test_runner: $(CORE_SRCS) $(APP_SRCS) $(TEST_DIR)/TestRunner.swift $(TEST_DIR)/ParserTests.swift $(TEST_DIR)/FeatureTests.swift $(TEST_DIR)/main.swift | $(BUILD_DIR)
	$(SWIFTC) $(SWIFT_FLAGS) \
		$(CORE_SRCS) $(APP_SRCS) \
		$(TEST_DIR)/TestRunner.swift $(TEST_DIR)/ParserTests.swift $(TEST_DIR)/FeatureTests.swift $(TEST_DIR)/main.swift \
		-framework AppKit \
		-o $@

# For App: compile everything including App.swift, excluding test files
$(BUILD_DIR)/MarkdownEditor: $(CORE_SRCS) $(APP_SRCS) $(EDITOR_SRCS) $(PREVIEW_SRCS) $(SPLIT_SRCS) $(SRC_DIR)/App.swift | $(BUILD_DIR)
	$(SWIFTC) $(SWIFT_FLAGS) \
		$(CORE_SRCS) $(APP_SRCS) $(EDITOR_SRCS) $(PREVIEW_SRCS) $(SPLIT_SRCS) $(SRC_DIR)/App.swift \
		$(FRAMEWORKS) \
		-o $@

test: $(BUILD_DIR)/test_runner
	@echo ""
	@echo "Running tests..."
	@$(BUILD_DIR)/test_runner

run: $(BUILD_DIR)/MarkdownEditor.app
	open $(BUILD_DIR)/MarkdownEditor.app

$(BUILD_DIR)/MarkdownEditor.app: $(BUILD_DIR)/MarkdownEditor
	mkdir -p $(BUILD_DIR)/MarkdownEditor.app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/MarkdownEditor.app/Contents/Resources
	cp $(BUILD_DIR)/MarkdownEditor $(BUILD_DIR)/MarkdownEditor.app/Contents/MacOS/
	cp Info.plist $(BUILD_DIR)/MarkdownEditor.app/Contents/
	touch $(BUILD_DIR)/MarkdownEditor.app

.PHONY: bundle
bundle: $(BUILD_DIR)/MarkdownEditor.app

clean:
	rm -rf $(BUILD_DIR)
