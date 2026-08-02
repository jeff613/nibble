APP := Nibble.app
BINARY := .build/release/Nibble

# `xcode-select` may point at CommandLineTools, which has no XCTest.
# Point the toolchain at Xcode when it is installed.
XCODE := /Applications/Xcode.app/Contents/Developer
SWIFT := $(if $(wildcard $(XCODE)),DEVELOPER_DIR=$(XCODE),) swift

.PHONY: app clean install test run icon

test:
	$(SWIFT) test

# The drawing code is the source of truth: edit it and the artwork rebuilds.
# Both steps live here so the .icns can never lag behind the PNGs.
Assets/Nibble.icns: Tools/GenerateIcon.swift
	$(SWIFT) Tools/GenerateIcon.swift Assets
	iconutil -c icns Assets/Nibble.iconset -o Assets/Nibble.icns
	@echo "Regenerated Assets/Nibble.icns and menu-bar glyphs."

# Force a redraw even when the code hasn't changed.
icon:
	rm -f Assets/Nibble.icns
	$(MAKE) Assets/Nibble.icns

run:
	$(SWIFT) run Nibble

$(BINARY): $(shell find Sources -name '*.swift') Package.swift
	$(SWIFT) build -c release

app: $(BINARY) Assets/Nibble.icns
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/Nibble
	cp Assets/Nibble.icns $(APP)/Contents/Resources/
	cp Assets/MenuBarIcon.png Assets/MenuBarIcon@2x.png $(APP)/Contents/Resources/
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>CFBundleIdentifier</key><string>com.nibble.app</string>' \
	  '  <key>CFBundleName</key><string>Nibble</string>' \
	  '  <key>CFBundleExecutable</key><string>Nibble</string>' \
	  '  <key>CFBundleIconFile</key><string>Nibble</string>' \
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
