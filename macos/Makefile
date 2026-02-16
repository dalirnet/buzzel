.PHONY: init
init:
	sh init.sh

.PHONY: build
build:
	sh build.sh

.PHONY: release
release:
	sh build.sh release

.PHONY: dist
dist: release
	cd build && zip -r Buzzel.zip Buzzel.app
	@echo "Done: build/Buzzel.zip"

.PHONY: run
run: build
	killall Buzzel 2>/dev/null || true
	sleep 0.5
	open build/Buzzel.app

.PHONY: clean
clean:
	rm -rf build .build
