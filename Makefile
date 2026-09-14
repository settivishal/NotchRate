# CLT-only build. 27.0 SDK needs Xcode's SwiftUI macro plugin; 26.5 SDK does not.
CLT   = /Library/Developer/CommandLineTools
SDK  ?= $(CLT)/SDKs/MacOSX26.5.sdk
FW    = $(CLT)/Library/Developer/Frameworks
APP   = build/NotchRate.app
SWIFT = SDKROOT=$(SDK) swift

.PHONY: build app run install test clean
build:
	$(SWIFT) build --build-system native -c release

app: build
	rm -rf $(APP); mkdir -p $(APP)/Contents/MacOS
	cp .build/release/NotchRate $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	codesign --force --sign - $(APP)

run: app
	pkill -x NotchRate || true
	open $(APP)

# Stable path so "Launch at login" (SMAppService) survives make clean.
install: app
	pkill -x NotchRate || true
	rm -rf /Applications/NotchRate.app && cp -R $(APP) /Applications/
	./install.sh
	open /Applications/NotchRate.app

test:
	$(SWIFT) test --build-system native -Xswiftc -F$(FW) -Xlinker -F$(FW) -Xlinker -rpath -Xlinker $(FW)

clean:
	rm -rf .build build
