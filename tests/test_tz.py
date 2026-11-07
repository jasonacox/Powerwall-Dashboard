"""Tests for tz.sh (run with: python3 -m pytest tests)."""
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
FILES = ["tz", "tz.sh", "telegraf.conf", "influxdb/influxdb.sql", "dashboards"]


@pytest.fixture
def install(tmp_path):
    """A copy of the files tz.sh rewrites, plus a pypowerwall.env from the sample."""
    for name in FILES:
        src = REPO / name
        if src.is_dir():
            shutil.copytree(src, tmp_path / name)
        else:
            (tmp_path / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, tmp_path / name)
    shutil.copy2(REPO / "pypowerwall.env.sample", tmp_path / "pypowerwall.env")
    return tmp_path


def tz(install, value):
    subprocess.run(["bash", "tz.sh", value], cwd=install, check=True, capture_output=True)


def snapshot(install):
    paths = ["telegraf.conf", "influxdb/influxdb.sql", "pypowerwall.env"]
    paths += sorted(str(p.relative_to(install)) for p in (install / "dashboards").glob("*.json"))
    return {p: (install / p).read_text() for p in paths}


def test_sets_every_timezone_setting(install):
    tz(install, "Europe/London")
    files = snapshot(install)
    assert 'timezone = "Europe/London"' in files["telegraf.conf"]
    assert "tz('Europe/London')" in files["influxdb/influxdb.sql"]
    assert "PW_TIMEZONE=Europe/London" in files["pypowerwall.env"]
    assert "TZ=Europe/London" in files["pypowerwall.env"]
    assert '"value": "Europe/London"' in files["dashboards/dashboard.json"]
    assert not any("America/Los_Angeles" in text for text in files.values())


@pytest.mark.parametrize("current", ["UTC", "GMT", "EST"])
def test_changing_from_short_zone_only_touches_timezone_settings(install, current):
    """A zone name like UTC also appears in code and comments (Date.UTC() in the
    Sun and Moon panel, telegraf.conf docs); changing away from it must leave those alone."""
    before = snapshot(install)
    tz(install, current)
    tz(install, "America/Los_Angeles")
    assert snapshot(install) == before
