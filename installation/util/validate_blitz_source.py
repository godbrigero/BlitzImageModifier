"""Reject mismatched/old source before any dependency or service installation."""
from pathlib import Path
import sys


def validate_source(root: Path) -> None:
    version_file = root / "backend/deployment/.blitz-build-version"
    try:
        version = version_file.read_text().strip()
        parts = tuple(int(part) for part in version.split("."))
    except (OSError, ValueError) as error:
        raise RuntimeError("Missing or invalid BLITZ deployment version; require 1.2.0 or later") from error
    if len(parts) != 3 or parts < (1, 2, 0):
        raise RuntimeError("BLITZ deployment {} is too old; require 1.2.0 or later".format(version))
    print("Selected BLITZ deployment source: {}".format(version))


if __name__ == "__main__":
    validate_source(Path(sys.argv[1]))
