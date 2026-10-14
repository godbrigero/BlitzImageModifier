#!/bin/bash
set -euo pipefail

INSTALLATION_DIR="${BLITZ_INSTALLATION_DIR:-/opt/blitz}"
DEFAULT_PI_NAME="${BLITZ_DEFAULT_PI_NAME:-blitz-pi-random-name-1234}"
BLITZ_GIT_URL="${BLITZ_GIT_URL:-https://github.com/PinewoodRobotics/B.L.I.T.Z.git}"
BLITZ_REF="${BLITZ_REF:-HEAD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$INSTALLATION_DIR/B.L.I.T.Z"

mkdir -p "$INSTALLATION_DIR"
if [ -e "$SOURCE_DIR" ] && [ "${BLITZ_RESUME_INSTALL:-false}" != true ]; then
    echo "BLITZ destination already exists: $SOURCE_DIR. Use a fresh image/install directory." >&2
    exit 1
fi

# The installer, setup script, and runtime must come from the same checkout.
if [ -e "$SOURCE_DIR" ]; then
    echo "Resuming BLITZ setup from existing checkout: $SOURCE_DIR"
    echo "Existing source is preserved; BLITZ_REF and BLITZ_SOURCE_DIR are not reapplied."
    if [ -z "${BLITZ_DEFAULT_PI_NAME:-}" ] && [ -s "$SOURCE_DIR/system_data/name.txt" ]; then
        DEFAULT_PI_NAME="$(cat "$SOURCE_DIR/system_data/name.txt")"
    fi
elif [ -n "${BLITZ_SOURCE_DIR:-}" ]; then
    if [ ! -f "$BLITZ_SOURCE_DIR/scripts/ui/install_on_system.sh" ]; then
        echo "BLITZ_SOURCE_DIR must point to a complete BLITZ source tree." >&2
        exit 1
    fi
    mkdir -p "$SOURCE_DIR"
    # Copy working-tree changes while excluding development caches/artifacts.
    rsync -a --exclude='.git' --exclude='.venv' --exclude='build' \
        --exclude='__pycache__' --exclude='.pytest_cache' --exclude='node_modules' \
        --exclude='*.egg-info' --exclude='.env*' --exclude='system_data/name.txt' \
        --exclude='website' --exclude='.ssh' "$BLITZ_SOURCE_DIR/" "$SOURCE_DIR/"
else
    git clone "$BLITZ_GIT_URL" "$SOURCE_DIR"
    if git -C "$SOURCE_DIR" rev-parse --verify "${BLITZ_REF}^{commit}" >/dev/null 2>&1; then
        git -C "$SOURCE_DIR" checkout --detach "$BLITZ_REF"
    else
        git -C "$SOURCE_DIR" checkout --detach "origin/$BLITZ_REF"
    fi
fi

# Never download a separate installer: its paths may disagree with this checkout.
for required in scripts/ui/install_on_system.sh scripts/setup.sh Makefile \
    backend/deployment/module/catalog.py; do
    if [ ! -f "$SOURCE_DIR/$required" ]; then
        echo "Incompatible or incomplete BLITZ checkout: missing $required in $SOURCE_DIR." >&2
        echo "Update this checkout to BLITZ 3.0.0 or later, then retry. No existing files were deleted." >&2
        exit 1
    fi
done

# Check source compatibility before installing dependencies or starting services.
python3 "$SCRIPT_DIR/../util/validate_blitz_source.py" "$SOURCE_DIR"

# Select the same interpreter installed by installation_common. Do not replace
# distro Python or rely on PATH changes made in a different shell.
PYTHON_BINARY="${BLITZ_PYTHON_BINARY:-/usr/bin/python3}"
if [ -z "${BLITZ_PYTHON_BINARY:-}" ] && [ "${BLITZ_DEVICE:-}" != pi5 ]; then
    if [ "${BLITZ_PYTHON_MODE:-auto}" = managed ] || \
        { [ "${BLITZ_PYTHON_MODE:-auto}" = auto ] && ! "$PYTHON_BINARY" -c 'import sys; sys.exit(sys.version_info < (3, 11))'; }; then
        PYTHON_BINARY="$HOME/.pyenv/versions/${BLITZ_PYTHON_VERSION:-3.12.6}/bin/python"
    fi
fi
if [ ! -x "$PYTHON_BINARY" ]; then
    echo "BLITZ Python interpreter missing: $PYTHON_BINARY. Run installation_common.bash first." >&2
    exit 1
fi
if [ ! -x "$SOURCE_DIR/.venv/bin/python" ]; then
    if [ "${BLITZ_PYTHON_SYSTEM_PACKAGES:-false}" = true ]; then
        "$PYTHON_BINARY" -m venv --system-site-packages "$SOURCE_DIR/.venv"
    else
        "$PYTHON_BINARY" -m venv "$SOURCE_DIR/.venv"
    fi
elif [ "${BLITZ_PYTHON_SYSTEM_PACKAGES:-false}" = true ]; then
    # Repair a resumed Pi install made with an isolated environment.
    "$PYTHON_BINARY" -m venv --system-site-packages "$SOURCE_DIR/.venv"
fi

# Older JetPack/Ubuntu ships protoc too old for modern protobuf runtimes. Use a
# compiler resolved together with this checkout's Python requirements, without
# replacing the distro compiler. PATH applies only to this installation.
"$SOURCE_DIR/.venv/bin/python" -m pip install -e "$SOURCE_DIR" grpcio-tools
cat > "$SOURCE_DIR/.venv/bin/protoc" <<'PROTOC'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/python" -m grpc_tools.protoc "$@"
PROTOC
chmod +x "$SOURCE_DIR/.venv/bin/protoc"
export PATH="$SOURCE_DIR/.venv/bin:$PATH"

TARGET_NAME="$DEFAULT_PI_NAME" \
TARGET_FOLDER="$INSTALLATION_DIR" \
SERVICE_NAME="blitz-startup" \
SERVICE_USER="${BLITZ_USER:-ubuntu}" \
DEV_LOCAL_OVERRIDE=true \
BLITZ_ASSUME_YES=true \
bash "$SOURCE_DIR/scripts/ui/install_on_system.sh"

# Fail image creation immediately if target runtime and deployment APIs disagree.
cd "$SOURCE_DIR"
BLITZ_PATH="$SOURCE_DIR" .venv/bin/python "$SCRIPT_DIR/../util/check_blitz_runtime.py"
