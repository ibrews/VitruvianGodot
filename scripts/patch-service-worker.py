#!/usr/bin/env python3
"""Serve Godot's cached application shell for offline PWA navigations."""

from pathlib import Path
import sys


worker = Path(sys.argv[1])
source = worker.read_text(encoding="utf-8")
needle = """\t\t\t\tlet cached = await cache.match(event.request);
\t\t\t\tif (cached != null) {"""
replacement = """\t\t\t\tlet cached = await cache.match(event.request);
\t\t\t\t// Godot pre-caches index.html, while sites are commonly opened at `/`.
\t\t\t\tif (cached == null && isNavigate) {
\t\t\t\t\tcached = await cache.match(CACHED_FILES[0]);
\t\t\t\t}
\t\t\t\tif (cached != null) {"""

if needle not in source:
	raise SystemExit(f"expected Godot service-worker block not found in {worker}")

worker.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
