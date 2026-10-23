# Meal Planner & Recipes build entry points. The Xcode project is generated from project.yml.

PROJECT  := MealPlanner.xcodeproj
SCHEME   := MealPlanner
PACKAGE  := Packages/MealKit
DERIVED  := build/DerivedData
PRODUCTS := $(DERIVED)/Build/Products
APP      := MealPlanner.app
ICONS    := Apps/MealPlanner/Resources/Assets.xcassets
MCP_TOOL := Contents/Helpers/meal-planner-mcp

# Automatic signing (team 6S43T3N4UL) may need to register the App ID or this Mac.
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) \
	-allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet

SWIFT_SOURCES := Apps $(PACKAGE)/Package.swift $(PACKAGE)/Sources $(PACKAGE)/Tests

.DEFAULT_GOAL := build
.PHONY: project build test test-package test-app run install mcp-inspect format lint perf seed icon clean

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

icon:
	swift Tools/icon/draw_icon.swift "$(ICONS)/AppIcon.appiconset" release
	swift Tools/icon/draw_icon.swift "$(ICONS)/AppIconDebug.appiconset" debug

mcp-inspect: build
	npx -y @modelcontextprotocol/inspector "$(PRODUCTS)/Debug/$(APP)/$(MCP_TOOL)"

format:
	xcrun swift-format format --in-place --recursive $(SWIFT_SOURCES)

lint:
	xcrun swift-format lint --strict --recursive $(SWIFT_SOURCES)

# The list budget (first block under 50 ms, search and order under 100 ms on 20 000 products and 5 000 recipes) is for
# optimized builds.
perf:
	MEAL_PERF=1 swift test --package-path $(PACKAGE) -c release -Xswiftc -enable-testing --filter "PerformanceTests"

# Rebuilds the starting product base from Tools/seed/catalog.py. USDA is the unpacked
# FoodData_Central_sr_legacy_food_csv_2018-04 folder from https://fdc.nal.usda.gov/download-datasets.
seed:
	@test -n "$(USDA)" || (echo 'usage: make seed USDA=<folder of the SR Legacy CSV files>' && exit 1)
	python3 -I Tools/seed/build.py "$(USDA)"

clean:
	rm -rf build $(PACKAGE)/.build
