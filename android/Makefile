.PHONY: init
init:
	sh init.sh

.PHONY: format
format:
	sh format.sh

.PHONY: build
build:
	sh build.sh

.PHONY: release
release:
	sh build.sh release

.PHONY: dist
dist: release
	@apk=$$(find app/build/outputs/apk/release -name '*.apk' | head -1) && \
	echo "Done: $$apk"

.PHONY: run
run: build
	adb install -r $$(find app/build/outputs/apk/debug -name '*.apk' | head -1)
	adb shell am start -n com.buzzel/.ui.MainActivity

.PHONY: test
test:
	./gradlew testDebugUnitTest

.PHONY: clean
clean:
	./gradlew clean
