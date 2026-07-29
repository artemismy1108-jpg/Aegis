SWIFTC := swiftc
BUILD_DIR := .build
BIN := $(BUILD_DIR)/aegis
APP_NAME := Aegis
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
APP_BIN := $(APP_DIR)/Contents/MacOS/$(APP_NAME)

.PHONY: build app run-app install-app smoke clean

build:
	mkdir -p $(BUILD_DIR)
	$(SWIFTC) -module-cache-path $(BUILD_DIR)/module-cache Sources/Aegis/main.swift -o $(BIN)

app: build
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BIN) $(APP_DIR)/Contents/Resources/aegis
	cp Fixtures/openrouter-models.sample.json $(APP_DIR)/Contents/Resources/openrouter-models.sample.json
	cp App/Info.plist $(APP_DIR)/Contents/Info.plist
	$(SWIFTC) -module-cache-path $(BUILD_DIR)/module-cache -framework AppKit Sources/AegisMenu/main.swift -o $(APP_BIN)

run-app: app
	open $(APP_DIR)

install-app: app
	cp -R $(APP_DIR) /Applications/$(APP_NAME).app

smoke: build
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) setup
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) doctor
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) status
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) scan --suggest
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) export codex
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) price-watch Fixtures/openrouter-models.sample.json

clean:
	rm -rf $(BUILD_DIR)
