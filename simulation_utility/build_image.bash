#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BLITZ_REF="${BLITZ_REF:-HEAD}"
BLITZ_GIT_URL="${BLITZ_GIT_URL:-https://github.com/PinewoodRobotics/B.L.I.T.Z.git}"

# Explicit source selection wins. A selected Git revision/repository uses Git;
# otherwise include the sibling working tree when developing both repositories.
if [ "${BLITZ_SOURCE_DIR+x}" = x ]; then
    source_dir="$BLITZ_SOURCE_DIR"
elif [ "$BLITZ_REF" = HEAD ] && \
    [ "$BLITZ_GIT_URL" = https://github.com/PinewoodRobotics/B.L.I.T.Z.git ] && \
    [ -d "$PROJECT_DIR/../BLITZ" ]; then
    source_dir="$PROJECT_DIR/../BLITZ"
else
    source_dir=""
fi

if [ -n "$source_dir" ]; then
    for required in scripts/ui/install_on_system.sh scripts/setup.sh Makefile \
        backend/deployment/module/catalog.py; do
        if [ ! -f "$source_dir/$required" ]; then
            echo "Incomplete BLITZ_SOURCE_DIR: missing $required in $source_dir" >&2
            exit 1
        fi
    done
    source_dir="$(cd "$source_dir" && pwd)"
    echo "Building simulator with local BLITZ working tree: $source_dir"
else
    echo "Building simulator with Git BLITZ: $BLITZ_GIT_URL ($BLITZ_REF)"
fi

# Stage only image inputs. Never send the developer's venv, credentials, device
# name, or build artifacts to Docker, including when the source is outside BIM.
context_dir="$(mktemp -d "${TMPDIR:-/tmp}/blitz-sim-build.XXXXXX")"
trap 'rm -rf "$context_dir"' EXIT
mkdir -p "$context_dir/installation" "$context_dir/simulation_utility" "$context_dir/blitz-source"
rsync -a --exclude='cached_images' --exclude='__pycache__' \
    --exclude='.env*' "$PROJECT_DIR/installation/" "$context_dir/installation/"
cp "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR/entrypoint.bash" "$context_dir/simulation_utility/"
if [ -n "$source_dir" ]; then
    rsync -a --exclude='.git' --exclude='.venv' --exclude='build' \
        --exclude='__pycache__' --exclude='.pytest_cache' --exclude='node_modules' \
        --exclude='*.egg-info' --exclude='.env*' --exclude='system_data/name.txt' \
        --exclude='website' --exclude='.ssh' "$source_dir/" "$context_dir/blitz-source/"
fi
docker build --build-arg "BLITZ_REF=$BLITZ_REF" --build-arg "BLITZ_GIT_URL=$BLITZ_GIT_URL" \
    -f "$context_dir/simulation_utility/Dockerfile" -t "${SIM_IMAGE:-blitz-sim:latest}" "$context_dir"
