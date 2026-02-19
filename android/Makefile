.PHONY: check
check:
	sh scripts/check.sh

.PHONY: assets
assets:
	sh scripts/assets.sh

.PHONY: format
format:
	sh scripts/format.sh

.PHONY: build
build:
	sh scripts/compile.sh

.PHONY: release
release:
	sh scripts/compile.sh release

.PHONY: test
test:
	./gradlew testDebugUnitTest

.PHONY: run
run: build
	adb install -r -t $$(find app/build/outputs/apk/debug -name '*.apk' | head -1)
	adb shell am start -n com.buzzel/.ui.SplashActivity

.PHONY: dist
dist: release
	@apk=$$(find app/build/outputs/apk/release -name '*.apk' | head -1) && \
	echo "Done: $$apk"

.PHONY: clean
clean:
	sh scripts/clean.sh
