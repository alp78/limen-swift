SIM ?= iPhone 17 Pro
# By UDID for install, launch and screenshots: two simulators can carry one name across runtimes.
SIM_ID ?= 6F9172CC-DF86-4F05-9EB3-42E8E287668F
DEVICE_ID ?= D5A6144A-6100-5A25-90E7-898D11325105
BUNDLE_ID ?= dev.peringer.limen
WORKSPACE := Limen.xcworkspace
DEST := platform=iOS Simulator,id=$(SIM_ID)

.DEFAULT_GOAL := help
.PHONY: help strings phones marks gen build test kit-test lint fmt run icon device clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

strings: ## Regenerate Str.swift from the Android Strings.kt
	python3 tools/strings.py

phones: ## Regenerate the phone number metadata from the pinned libphonenumber release
	python3 tools/phones.py

marks: ## Copy the seal, the flags and the mark from the Android repository into the asset catalog
	bash tools/sync-marks.sh

gen: ## Regenerate the Xcode project from Project.swift
	tuist generate --no-open

build: ## Build the app for the simulator
	set -o pipefail && xcodebuild -workspace $(WORKSPACE) -scheme Limen \
		-destination '$(DEST)' -derivedDataPath ./DD build | xcbeautify --quiet

test: ## Run the AllTests scheme
	set -o pipefail && xcodebuild -workspace $(WORKSPACE) -scheme AllTests \
		-destination '$(DEST)' -derivedDataPath ./DD test | xcbeautify --quiet

kit-test: ## Run the LimenKit suite only
	set -o pipefail && xcodebuild -workspace $(WORKSPACE) -scheme LimenKit \
		-destination '$(DEST)' -derivedDataPath ./DD test | xcbeautify --quiet

lint: ## SwiftLint over the sources
	swiftlint lint --quiet

fmt: ## swift-format in place
	xcrun swift-format format --in-place --recursive LimenKit Limen LimenTests LimenKitTests LimenUITests

run: build ## Build, install and launch on the simulator
	@xcrun simctl boot "$(SIM_ID)" 2>/dev/null || true
	@xcrun simctl install "$(SIM_ID)" ./DD/Build/Products/Debug-iphonesimulator/Limen.app
	@xcrun simctl launch "$(SIM_ID)" $(BUNDLE_ID)
	@open -a Simulator

icon: ## Regenerate the app icon from the seal (runs the icon test, copies the PNG)
	set -o pipefail && xcodebuild -workspace $(WORKSPACE) -scheme AllTests -only-testing:LimenTests/AppIconTests \
		-destination '$(DEST)' -derivedDataPath ./DD test 2>&1 | tee DD/icon.log | xcbeautify --quiet; \
	cp "$$(grep -o 'LIMEN_ICON_WRITTEN .*' DD/icon.log | head -1 | cut -d' ' -f2)" Limen/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png

device: ## Build Release and install + launch on the connected iPhone
	# The destination names the phone rather than 'generic/platform=iOS': a free team registers a
	# device only when the build is aimed at it, and without that there is no profile to sign with.
	set -o pipefail && xcodebuild -workspace $(WORKSPACE) -scheme Limen \
		-destination 'id=$(DEVICE_ID)' -configuration Release \
		-derivedDataPath ./DD -allowProvisioningUpdates build | xcbeautify --quiet
	xcrun devicectl device install app --device $(DEVICE_ID) ./DD/Build/Products/Release-iphoneos/Limen.app
	xcrun devicectl device process launch --device $(DEVICE_ID) $(BUNDLE_ID)

clean: ## Remove generated project and build output
	rm -rf DD *.xcodeproj *.xcworkspace Derived .tuist
