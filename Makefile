APP   = build/NotchRate.app

.PHONY: build app run install test clean
build:
	swift build -c release

app: build
	rm -rf $(APP); mkdir -p $(APP)/Contents/MacOS
	cp .build/release/NotchRate $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	mkdir -p $(APP)/Contents/Resources && cp adapters/claude-code.sh $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)

run: app
	pkill -x NotchRate || true
	open $(APP)

# Stable path so "Launch at login" (SMAppService) survives make clean.
# Status-line hook is wired from the app itself (menu → Connect Claude Code status line).
install: app
	pkill -x NotchRate || true
	rm -rf /Applications/NotchRate.app && cp -R $(APP) /Applications/
	open /Applications/NotchRate.app

test:
	swift test

clean:
	rm -rf .build build
