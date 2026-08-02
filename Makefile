APP := UsageBar.app
BINARY := .build/release/UsageBar

# `xcode-select` may point at CommandLineTools, which has no XCTest.
# Point the toolchain at Xcode when it is installed.
XCODE := /Applications/Xcode.app/Contents/Developer
SWIFT := $(if $(wildcard $(XCODE)),DEVELOPER_DIR=$(XCODE),) swift

.PHONY: app clean install test run

test:
	$(SWIFT) test

run:
	$(SWIFT) run UsageBar

$(BINARY): $(shell find Sources -name '*.swift') Package.swift
	$(SWIFT) build -c release

app: $(BINARY)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/UsageBar
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>CFBundleIdentifier</key><string>com.usagebar.app</string>' \
	  '  <key>CFBundleName</key><string>UsageBar</string>' \
	  '  <key>CFBundleExecutable</key><string>UsageBar</string>' \
	  '  <key>CFBundlePackageType</key><string>APPL</string>' \
	  '  <key>CFBundleShortVersionString</key><string>1.0</string>' \
	  '  <key>LSMinimumSystemVersion</key><string>14.0</string>' \
	  '  <key>LSUIElement</key><true/>' \
	  '</dict></plist>' > $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)
	@echo "Built $(APP) — run 'make install' to move it to /Applications."

install: app
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/
	open /Applications/$(APP)

clean:
	rm -rf .build $(APP)
