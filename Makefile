.PHONY: help build test check package
.DEFAULT_GOAL := help

help:
	@printf '%s\n' 'make build    Build the native app' 'make test     Run offline fixture tests' 'make check    Test and verify the app locally' 'make package  Test and create a DMG + SHA-256 checksum'

build:
	sh build.sh

test:
	@mkdir -p build
	xcrun swiftc -swift-version 5 Core.swift Tests.swift -o build/core-tests
	build/core-tests
	xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 -D RENDER_TESTS Core.swift App.swift RenderTests.swift -o build/render-tests -framework AppKit -framework ServiceManagement
	build/render-tests

check: test build
	sh -n build.sh
	sh -n build-dmg.sh
	plutil -lint build/oh-my-usage.app/Contents/Info.plist
	git diff --check

package: test
	sh build-dmg.sh
