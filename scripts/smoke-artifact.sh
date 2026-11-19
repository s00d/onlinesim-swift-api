#!/usr/bin/env bash
# Smoke test of the package as SwiftPM gets it: a clean copy of the tracked files (`git archive HEAD` on a clean
# checkout; the files git would commit otherwise), used through `.package(path:)` by an empty executable package
# that runs the README "Testing" example against MockOnlineSim (offline). Work dir: .build/smoke-artifact.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work="$root/.build/smoke-artifact"
pkg="$work/onlinesim-swift-api"
app="$work/app"
rm -rf "$work"
mkdir -p "$pkg" "$app/Sources/App"

if git -C "$root" rev-parse -q --verify HEAD > /dev/null && [ -z "$(git -C "$root" status --porcelain)" ]; then
  git -C "$root" archive --format=tar HEAD | tar -x -C "$pkg"
  echo "copy: git archive HEAD"
else
  (cd "$root" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf -) | tar -x -C "$pkg"
  echo "copy: tracked + untracked files (no commit yet)"
fi
for f in Package.swift README.md LICENSE CHANGELOG.md Sources/OnlineSim/Client.swift; do
  [ -f "$pkg/$f" ] || { echo "missing $f in the copy" >&2; exit 1; }
done
for d in .build .swiftpm docs/node_modules docs/.output; do
  [ ! -e "$pkg/$d" ] || { echo "stray $d in the copy" >&2; exit 1; }
done

cat > "$app/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmokeApp",
    platforms: [.macOS(.v12)],
    dependencies: [.package(path: "../onlinesim-swift-api")],
    targets: [
        .executableTarget(name: "App", dependencies: [.product(name: "OnlineSim", package: "onlinesim-swift-api")])
    ]
)
SWIFT

# The first ```swift block after "## Testing" in the copied README.
awk '/^## Testing/ { t = 1 } t && /^```swift/ { b = 1; next } b && /^```/ { exit } b { print }' "$pkg/README.md" \
  > "$app/Sources/App/main.swift"
[ -s "$app/Sources/App/main.swift" ] || { echo 'README.md has no "## Testing" swift example' >&2; exit 1; }

swift run -c release --package-path "$app" App
echo 'README "Testing" example: ok'
