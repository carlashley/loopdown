#!/bin/sh
set -eu

# build.sh
# Build a compressed zipapp at ./dist/loopdown with dependencies from requirements.txt
# vendored inside the zipapp.
#
# Guarantees:
#   - NEVER installs requirements into the machine Python environment.
#   - Uses an isolated temporary venv for pip/zipapp tooling.
#   - Installs dependencies ONLY into a temporary build dir via pip --target.
#
# Usage:
#   ./build.sh --build-python=/opt/homebrew/bin/python3
#   ./build.sh --build-python=/usr/local/bin/python3 --interpreter="/usr/bin/env python3"

TARGET_INTERPRETER="/usr/bin/env python3"
BUILD_PYTHON=""
MAIN="loopdown.__main__:main"

usage() {
  cat <<'EOF'
Usage: ./build.sh --build-python=<python> [--interpreter=<shebang>] [--main=<module:callable>]

Required:
  --build-python=...   Python executable used to create an isolated venv for the build.

Optional:
  --interpreter=...    Shebang/interpreter embedded in the zipapp (default: /usr/bin/env python3)
                       This is the *target* runtime and does NOT have to exist on the build machine.
  --main=...           Zipapp entrypoint (default: loopdown.__main__:main)
  -h, --help           Show help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --build-python=*) BUILD_PYTHON=${arg#*=} ;;
    --interpreter=*)  TARGET_INTERPRETER=${arg#*=} ;;
    --main=*)         MAIN=${arg#*=} ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$BUILD_PYTHON" ]; then
  echo "ERROR: --build-python is required (no auto-detection)." >&2
  usage >&2
  exit 2
fi

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

BUILD_EXE="$BUILD_PYTHON"
if [ ! -x "$BUILD_EXE" ]; then
  echo "ERROR: build python is not an executable file: $BUILD_EXE" >&2
  exit 1
fi

if ! "$BUILD_EXE" -c 'import sys; raise SystemExit(0)' >/dev/null 2>&1; then
  echo "ERROR: build python is not runnable: $BUILD_EXE" >&2
  exit 1
fi

WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t loopdown_build)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM

VENV_DIR="$WORKDIR/venv"
BUILDDIR="$WORKDIR/build"
mkdir -p "$BUILDDIR"

# Create an isolated venv for build tooling (pip + zipapp)
"$BUILD_EXE" -m venv "$VENV_DIR"

VENV_PY="$VENV_DIR/bin/python"
if [ ! -x "$VENV_PY" ]; then
  echo "ERROR: venv python not found at: $VENV_PY" >&2
  exit 1
fi

# Make pip deterministic and avoid user/site leakage.
# - Prevent reading user pip config and writing caches to your home dir.
# - Prevent user site-packages from being considered.
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
export PIP_CONFIG_FILE=/dev/null
export PIP_CACHE_DIR="$WORKDIR/pip-cache"
export PYTHONNOUSERSITE=1

# Ensure pip exists inside venv and upgrade it (only inside venv)
"$VENV_PY" -m pip --version >/dev/null 2>&1 || "$VENV_PY" -m ensurepip --upgrade >/dev/null 2>&1
"$VENV_PY" -m pip install --upgrade pip >/dev/null

# Install deps ONLY into the zipapp build dir, not into the venv site-packages.
"$VENV_PY" -m pip install --no-compile \
  --target "$BUILDDIR" \
  -r "$REQ"

# Copy app package into build dir
mkdir -p "$BUILDDIR/loopdown"
cp -R "$PKG_SRC/"* "$BUILDDIR/loopdown/"

# Build zipapp
mkdir -p "$DIST_DIR"
rm -f "$OUT"

"$VENV_PY" -m zipapp "$BUILDDIR" \
  -o "$OUT" \
  -p "$TARGET_INTERPRETER" \
  -m "$MAIN" \
  -c

chmod +x "$OUT"

echo "Built zipapp: $OUT"
echo "Embedded shebang: #!$TARGET_INTERPRETER"
echo "Build python used (to create venv): $BUILD_EXE"
