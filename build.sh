#!/bin/sh
set -eu

# build.sh
# Build a compressed zipapp at ./dist/loopdown with deps from requirements.txt
# vendored inside the zipapp.
#
# Builder vs target:
#   --build-python=...  Python used to run pip + zipapp during the build (MUST exist)
#   --interpreter=...   Shebang string embedded in the zipapp (may differ; need not exist)
#
# Defaults:
#   --interpreter="/usr/bin/env python3"
#   --build-python=python3 (if available on PATH)

TARGET_INTERPRETER="/usr/bin/env python3"
BUILD_PYTHON=""
MAIN="loopdown.__main__:main"

usage() {
  cat <<'EOF'
Usage: ./build.sh [options]

Options:
  --build-python=...   Python to use for building (pip + zipapp). If omitted, uses python3 on PATH.
                       Examples:
                         --build-python=/opt/python/bin/python3
                         --build-python=/usr/local/bin/python3

  --interpreter=...    Interpreter string embedded in the zipapp shebang (default: /usr/bin/env python3)
                       Examples:
                         --interpreter=/usr/local/bin/python3
                         --interpreter="/usr/bin/env python3"

  --main=...           Zipapp entrypoint (default: loopdown.__main__:main)

  -h, --help           Show help
EOF
}

# Parse args
for arg in "$@"; do
  case "$arg" in
    --build-python=*) BUILD_PYTHON=${arg#*=} ;;
    --interpreter=*)  TARGET_INTERPRETER=${arg#*=} ;;
    --main=*)         MAIN=${arg#*=} ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DIST_DIR="$SCRIPT_DIR/dist"
OUT="$DIST_DIR/loopdown"
REQ="$SCRIPT_DIR/requirements.txt"
PKG_SRC="$SCRIPT_DIR/src/loopdown"

if [ ! -f "$REQ" ]; then
  echo "requirements.txt not found at: $REQ" >&2
  exit 1
fi

if [ ! -d "$PKG_SRC" ]; then
  echo "Package source not found at: $PKG_SRC" >&2
  echo "Expected layout: ./src/loopdown/ (relative to build.sh)" >&2
  exit 1
fi

# Choose build python if not provided
if [ -z "$BUILD_PYTHON" ]; then
  if command -v python3 >/dev/null 2>&1; then
    BUILD_PYTHON="python3"
  else
    echo "No --build-python provided and python3 not found on PATH." >&2
    echo "Provide one, e.g.: ./build.sh --build-python=/opt/python/bin/python3" >&2
    exit 1
  fi
fi

# Resolve build python executable.
# IMPORTANT: We intentionally require BUILD_PYTHON to be a single executable path/name.
# If you need env, do: --build-python=/usr/bin/python3 (or ensure python3 is on PATH).
BUILD_EXE="$BUILD_PYTHON"

# Sanity check: build python must be runnable
if ! "$BUILD_EXE" -c 'import sys; raise SystemExit(0)' >/dev/null 2>&1; then
  echo "Build Python is not runnable: $BUILD_EXE" >&2
  exit 1
fi

WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t loopdown_build)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM

BUILDDIR="$WORKDIR/build"
mkdir -p "$BUILDDIR"

# Ensure pip exists for build python
if ! "$BUILD_EXE" -m pip --version >/dev/null 2>&1; then
  echo "pip is not available for build python: $BUILD_EXE" >&2
  echo "Try: $BUILD_EXE -m ensurepip --upgrade" >&2
  exit 1
fi

# Vendor dependencies into build dir
"$BUILD_EXE" -m pip install --upgrade pip >/dev/null
"$BUILD_EXE" -m pip install --no-compile --disable-pip-version-check \
  --target "$BUILDDIR" -r "$REQ"

# Copy app package into build dir
mkdir -p "$BUILDDIR/loopdown"
cp -R "$PKG_SRC/"* "$BUILDDIR/loopdown/"

# Build zipapp
mkdir -p "$DIST_DIR"
rm -f "$OUT"

"$BUILD_EXE" -m zipapp "$BUILDDIR" \
  -o "$OUT" \
  -p "$TARGET_INTERPRETER" \
  -m "$MAIN" \
  -c

chmod +x "$OUT"

echo "Built zipapp: $OUT"
echo "Embedded shebang: #!$TARGET_INTERPRETER"
echo "Build python used: $BUILD_EXE"
