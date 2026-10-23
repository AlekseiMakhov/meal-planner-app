#!/bin/bash
# Builds the installer image: the Release app with the recipe library of a data folder, signed again, and a link
# to Applications for installing by dragging. `make dmg` calls it.
# Usage: make_dmg.sh <built app> <data folder> [signing identity]
set -euo pipefail

app="$1"
data="$2"
identity="${3:-}"
out="build/dmg"
name="Meal Planner & Recipes"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")

rm -rf "$out"
mkdir -p "$out/image"
staged="$out/image/MealPlanner.app"
ditto "$app" "$staged"

swift run --package-path Packages/MealKit meal-library export "$data" "$staged/Contents/Resources/StarterLibrary"

# The library is new content in the app, so the app is signed again: by default with the build's own identity.
if [ -z "$identity" ]; then
    identity=$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
fi
stamp=""
case "$identity" in
    "Developer ID"*)
        # Distribution: the helper is signed with the same identity, both with a secure timestamp.
        stamp="--timestamp"
        codesign --force --options runtime --timestamp --sign "$identity" "$staged/Contents/Helpers/meal-planner-mcp"
        ;;
esac
# The project's own entitlements, not the build's: a development build adds get-task-allow, which an installed
# app does not need and notarization refuses.
codesign --force --options runtime $stamp --sign "$identity" --entitlements Config/MealPlanner.entitlements "$staged"
codesign --verify --deep --strict "$staged"

ln -s /Applications "$out/image/Программы"
image="$out/$name $version.dmg"
hdiutil create -quiet -volname "$name" -srcfolder "$out/image" -ov -format UDZO "$image"
echo "$image — подпись: $identity"
