# Command Line Tools ship the Swift Testing macro plugin outside the default search path.
DEV_DIR := $(shell xcode-select -p)
ifeq ($(DEV_DIR),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(DEV_DIR)/usr/lib/swift/host/plugins/testing
endif

.PHONY: build test test-ui adapter app run dist release clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

# The tests that open windows (settings sidebar, settings PNGs under $TMPDIR/PhoneBoxSettings), on their own: beside the
# timing tests they hold the main thread too long. Needs a logged-in GUI session.
test-ui:
	PHONEBOX_UI=1 swift test $(TEST_FLAGS) --filter 'SettingsSidebarTests|SettingsViewRenderTests'

adapter:
	scripts/build-adapter.sh

app:
	scripts/bundle.sh

run: app
	-pkill -x PhoneBox
	@tries=0; while pgrep -x PhoneBox >/dev/null; do \
		tries=$$((tries + 1)); \
		if [ $$tries -ge 50 ]; then echo "error: PhoneBox did not quit within 5 s" >&2; exit 1; fi; \
		sleep 0.1; \
	done
	open build/PhoneBox.app

# build/PhoneBox.app zipped into dist/PhoneBox-<version>.zip, its signature checked.
dist: app
	scripts/dist.sh

# Publishes a GitHub release from a clean, pushed main: make release VERSION=0.2.0 (DRY_RUN=1 to rehearse).
release:
	scripts/release.sh $(VERSION)

clean:
	rm -rf .build build dist
