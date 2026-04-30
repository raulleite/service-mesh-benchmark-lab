#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test -s "$ROOT/readme.md"
test -s "$ROOT/readme_us.md"
grep -q "Service Mesh Benchmark" "$ROOT/readme.md"
grep -q "Service Mesh Benchmark" "$ROOT/readme_us.md"
echo "Bilingual documentation is present"