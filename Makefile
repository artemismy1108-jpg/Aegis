SWIFTC := swiftc
BUILD_DIR := .build
BIN := $(BUILD_DIR)/aegis

.PHONY: build smoke clean

build:
	mkdir -p $(BUILD_DIR)
	$(SWIFTC) -module-cache-path $(BUILD_DIR)/module-cache Sources/Aegis/main.swift -o $(BIN)

smoke: build
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) init-sample
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) status
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) scan --suggest
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) export codex
	AEGIS_CONFIG=/private/tmp/aegis-smoke.json $(BIN) price-watch Fixtures/openrouter-models.sample.json

clean:
	rm -rf $(BUILD_DIR)
