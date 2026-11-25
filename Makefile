# Command Line Tools ship the Swift Testing macro plugin outside the default search path.
DEV_DIR := $(shell xcode-select -p)
ifeq ($(DEV_DIR),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(DEV_DIR)/usr/lib/swift/host/plugins/testing
endif

.PHONY: build test app run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)',)

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

clean:
	rm -rf .build build
