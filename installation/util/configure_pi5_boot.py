"""Maintain BLITZ's Pi 5 interface settings without replacing user boot config."""
from __future__ import annotations

from pathlib import Path
import re
import sys

BEGIN = "# BEGIN BLITZ Pi 5 interfaces"
END = "# END BLITZ Pi 5 interfaces"


def configure_boot_config(path: Path) -> None:
    original = path.read_text()
    previous = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", re.DOTALL)
    content = previous.sub("", original).rstrip() + "\n\n"
    content += f"{BEGIN}\n[all]\ncamera_auto_detect=1\ndtparam=i2c_arm=on\ndtparam=spi=on\n{END}\n"
    if content != original:
        path.write_text(content)


if __name__ == "__main__":
    configure_boot_config(Path(sys.argv[1]))
