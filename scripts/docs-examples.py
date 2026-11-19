#!/usr/bin/env python3
"""Compiles the Swift examples of README.md and docs/content/*.md against the package, so the docs cannot drift
from the API. A ```swift block is an example when it uses `client` or has an `import`; the other blocks are
signatures. Blocks with top-level declarations (func/class/struct) are compiled as they are; the rest are wrapped
in an async throwing function that gets `client: OnlineSimClient` and `tzid: Int` unless the block declares them.
Generates a throwaway package in .build/docs-examples and builds it (`swift build --build-tests`)."""
import pathlib
import re
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
out = root / ".build" / "docs-examples"
sources = [root / "README.md", *sorted((root / "docs" / "content").glob("*.md"))]

shutil.rmtree(out, ignore_errors=True)
tests = out / "Tests" / "DocsExamples"
tests.mkdir(parents=True)

count = 0
for source in sources:
    for i, block in enumerate(re.findall(r"^```swift[^\n]*\n(.*?)^```", source.read_text(), re.S | re.M)):
        if not re.search(r"\bclient\b|^import ", block, re.M):
            continue
        lines = block.splitlines()
        imports = [l for l in lines if l.startswith("import ")]
        body = [l for l in lines if not l.startswith("import ")]
        header = ["import Foundation", "import OnlineSim", *imports]
        if any(re.match(r"(@main|func |final class |class |struct |enum |extension )", l) for l in body):
            code = header + body
        else:
            params = []
            if not re.search(r"\b(let|var)\s+client\b", block):
                params.append("client: OnlineSimClient")
            if not re.search(r"\b(let|var)\s+tzid\b", block):
                params.append("tzid: Int")
            name = re.sub(r"\W", "_", f"{source.stem}_{i}")
            code = header + [f"func example_{name}({', '.join(params)}) async throws {{", *body, "}"]
        (tests / f"{re.sub(r'[^A-Za-z0-9]', '_', source.name)}_{i}.swift").write_text("\n".join(code) + "\n")
        count += 1

if count < 20:
    sys.exit(f"only {count} examples found")

(out / "Package.swift").write_text(f"""// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DocsExamples",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    dependencies: [.package(path: "{root}")],
    targets: [
        .testTarget(
            name: "DocsExamples",
            dependencies: [.product(name: "OnlineSim", package: "{root.name}")]
        )
    ]
)
""")
print(f"compiling {count} docs examples", flush=True)
sys.exit(subprocess.call(["swift", "build", "--build-tests", "--package-path", str(out)]))
