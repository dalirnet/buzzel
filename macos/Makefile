.PHONY: check
check:
	sh Scripts/check.sh

.PHONY: assets
assets:
	sh Scripts/assets.sh

.PHONY: format
format:
	sh Scripts/format.sh

.PHONY: build
build:
	sh Scripts/compile.sh

.PHONY: release
release:
	sh Scripts/compile.sh release

.PHONY: test
test:
	swiftc -o build/test-protocol \
		Sources/Services/Protocol.swift \
		Sources/Services/FrameCodec.swift \
		Tests/ProtocolTests.swift
	./build/test-protocol

.PHONY: run
run: build
	killall Buzzel 2>/dev/null || true
	sleep 0.5
	open build/Buzzel.app

.PHONY: dist
dist: release
	cd build && zip -r Buzzel.zip Buzzel.app
	@echo "Done: build/Buzzel.zip"

.PHONY: clean
clean:
	sh Scripts/clean.sh
