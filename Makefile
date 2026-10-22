# Meal Planner & Recipes build entry points. The Xcode project is generated from project.yml.

PROJECT  := MealPlanner.xcodeproj
SCHEME   := MealPlanner
PACKAGE  := Packages/MealKit
DERIVED  := build/DerivedData
PRODUCTS := $(DERIVED)/Build/Products
APP      := MealPlanner.app
MCP_TOOL := Contents/Helpers/meal-planner-mcp

# Automatic signing (team 6S43T3N4UL) may need to register the App ID or this Mac.
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) \
	-allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet

SWIFT_SOURCES := Apps $(PACKAGE)/Package.swift $(PACKAGE)/Sources $(PACKAGE)/Tests

.DEFAULT_GOAL := build
.PHONY: project build test test-package test-app run install mcp-inspect format lint clean

project:
	xcodegen generate --use-cache --quiet

build: project
	$(XCODEBUILD) -configuration Debug build

test: test-package test-app

test-package:
	swift test --package-path $(PACKAGE)

test-app: project
	$(XCODEBUILD) -configuration Debug test

run: build
	open "$(PRODUCTS)/Debug/$(APP)"

install: project
	$(XCODEBUILD) -configuration Release build
	-pkill -x MealPlanner
	rm -rf "/Applications/$(APP)"
	ditto "$(PRODUCTS)/Release/$(APP)" "/Applications/$(APP)"
	open "/Applications/$(APP)"

mcp-inspect: build
	npx -y @modelcontextprotocol/inspector "$(PRODUCTS)/Debug/$(APP)/$(MCP_TOOL)"

format:
	xcrun swift-format format --in-place --recursive $(SWIFT_SOURCES)

lint:
	xcrun swift-format lint --strict --recursive $(SWIFT_SOURCES)

clean:
	rm -rf build $(PACKAGE)/.build
