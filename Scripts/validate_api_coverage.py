#!/usr/bin/env python3
"""
Validate documented API routes in api.md against implemented routes in Services/.

Usage:
  python3 Scripts/validate_api_coverage.py
"""

from __future__ import annotations

import pathlib
import re
import sys


ROUTE_BLOCK_RE = re.compile(r"## Route\s*\n((?:`[^`]+`\s*\n?)+)")
BACKTICK_VALUE_RE = re.compile(r"`([^`]+)`")
METHOD_PREFIX_RE = re.compile(r"^(GET|POST|PATCH|DELETE|HEAD)\s+", re.IGNORECASE)
PLACEHOLDER_RE = re.compile(r"\{[^}]+\}")


def normalize_doc_route(raw: str) -> str:
    route = METHOD_PREFIX_RE.sub("", raw.strip())
    route = route.replace("/jsonapi.php", "")
    if not route.startswith("/v1"):
        route = "/v1" + route
    route = PLACEHOLDER_RE.sub("{id}", route)
    route = re.sub(r"/+", "/", route)
    if route != "/" and route.endswith("/"):
        route = route[:-1]
    return route


def normalize_swift_interpolations(swift_literal: str) -> str:
    # Replace every Swift interpolation segment '\(... )' with '{id}' while
    # handling nested parentheses inside the interpolation expression.
    result: list[str] = []
    i = 0
    n = len(swift_literal)

    while i < n:
        ch = swift_literal[i]
        if ch == "\\" and i + 1 < n and swift_literal[i + 1] == "(":
            i += 2
            depth = 1
            while i < n and depth > 0:
                cur = swift_literal[i]
                if cur == "(":
                    depth += 1
                elif cur == ")":
                    depth -= 1
                i += 1
            result.append("{id}")
            continue

        result.append(ch)
        i += 1

    return "".join(result)


def normalize_code_route(raw: str) -> str | None:
    route = normalize_swift_interpolations(raw.strip())
    if "/v1/" not in route and route != "/v1":
        return None
    route = PLACEHOLDER_RE.sub("{id}", route)
    route = re.sub(r"/+", "/", route)
    if route != "/" and route.endswith("/"):
        route = route[:-1]
    return route


def parse_documented_routes(api_md_path: pathlib.Path) -> set[str]:
    text = api_md_path.read_text(encoding="utf-8")
    routes: list[str] = []

    for block_match in ROUTE_BLOCK_RE.finditer(text):
        block = block_match.group(1)
        for value in BACKTICK_VALUE_RE.findall(block):
            routes.append(normalize_doc_route(value))

    # Preserve uniqueness through set; ordering is not required for validation.
    return set(routes)


def parse_implemented_routes(services_root: pathlib.Path) -> set[str]:
    routes: set[str] = set()
    collection_paths: set[str] = set()

    swift_files = sorted(services_root.rglob("*.swift"))
    for swift_file in swift_files:
        text = swift_file.read_text(encoding="utf-8", errors="ignore")

        for match in re.finditer(r'path:\s*"([^"]+)"', text):
            raw_literal = match.group(1)
            # Skip paths with unknown dynamic suffixes to avoid false positives
            # like "/v1/courses/{id}/{id}" from "/v1/courses/\(id)/\(suffix)".
            if "\\(suffix)" in raw_literal or "\\(section)" in raw_literal:
                continue

            normalized = normalize_code_route(raw_literal)
            if normalized:
                routes.add(normalized)

        for match in re.finditer(r'static let collectionPath = "([^"]+)"', text):
            normalized = normalize_code_route(match.group(1))
            if normalized:
                collection_paths.add(normalized)
                routes.add(normalized)

    for base in collection_paths:
        routes.add(f"{base}/{{id}}")

    # makeScopedPath in StudIPRepositoryUtilities builds these dynamic routes.
    routes.update(
        {
            "/v1/courses/{id}/file-refs",
            "/v1/institutes/{id}/file-refs",
            "/v1/users/{id}/file-refs",
            "/v1/courses/{id}/folders",
            "/v1/institutes/{id}/folders",
            "/v1/users/{id}/folders",
        }
    )

    return routes


def main() -> int:
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    api_md_path = repo_root / "api.md"
    services_root = repo_root / "StudipSync" / "Services"

    documented = parse_documented_routes(api_md_path)
    implemented = parse_implemented_routes(services_root)

    missing = sorted(documented - implemented)
    extra = sorted(implemented - documented)

    print(f"Documented routes: {len(documented)}")
    print(f"Implemented routes: {len(implemented)}")
    print(f"Missing routes: {len(missing)}")
    if missing:
        for route in missing:
            print(f"  - {route}")

    print(f"Undocumented implemented routes: {len(extra)}")
    # Keep output compact: only show a subset.
    for route in extra[:15]:
        print(f"  + {route}")
    if len(extra) > 15:
        print(f"  ... and {len(extra) - 15} more")

    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
