APP := .build/CodexPet.app
BIN := $(APP)/Contents/MacOS/CodexPet

.PHONY: build test install clean

build:
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources .build/AppIcon.iconset
	cp Info.plist $(APP)/Contents/Info.plist
	cp Assets/PetFrames/idle-[1-6].png Assets/PetFrames/typing-[1-6].png $(APP)/Contents/Resources/
	sips -z 16 16 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_16x16.png >/dev/null
	sips -z 32 32 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_16x16@2x.png >/dev/null
	sips -z 32 32 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_32x32.png >/dev/null
	sips -z 64 64 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_32x32@2x.png >/dev/null
	sips -z 128 128 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_128x128.png >/dev/null
	sips -z 256 256 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_256x256.png >/dev/null
	sips -z 512 512 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_512x512.png >/dev/null
	sips -z 1024 1024 Assets/AppIcon.png --out .build/AppIcon.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns .build/AppIcon.iconset -o $(APP)/Contents/Resources/AppIcon.icns
	clang -fobjc-arc -framework AppKit Sources/main.m -o $(BIN)

test: build
	$(BIN) --self-test

install: test
	./scripts/install.sh

clean:
	rm -rf .build
