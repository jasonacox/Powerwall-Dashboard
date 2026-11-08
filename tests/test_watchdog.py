"""Tests for watchdog.sh with stub docker/crontab commands (run with: python3 -m pytest tests)."""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent


def stub(bindir, name, body):
    path = bindir / name
    path.write_text("#!/bin/sh\n" + body + "\n")
    path.chmod(0o755)


@pytest.fixture
def env(tmp_path):
    """Install dir with watchdog.sh, a stub bin dir, and a log of stub calls."""
    install = tmp_path / "Powerwall-Dashboard"
    install.mkdir()
    shutil.copy2(REPO / "watchdog.sh", install / "watchdog.sh")
    bindir = tmp_path / "bin"
    bindir.mkdir()
    log = tmp_path / "calls.log"
    for tool in ("sh", "cat", "grep", "date", "dirname", "mktemp", "rm"):
        found = shutil.which(tool, path="/usr/bin:/bin")
        if found:
            os.symlink(found, bindir / tool)
    return {"install": install, "bin": bindir, "log": log, "tmp": tmp_path,
            "env": {"PATH": str(bindir), "HOME": str(tmp_path)}}


def run(env, *args, cwd=None, stdin=""):
    return subprocess.run(["/bin/bash", str(env["install"] / "watchdog.sh"), *args],
                          cwd=cwd or env["install"], env=env["env"], input=stdin,
                          capture_output=True, text=True)


def test_restarts_unhealthy_container(env):
    stub(env["bin"], "docker", f'echo "$@" >> {env["log"]}\n[ "$1" = inspect ] && echo unhealthy\nexit 0')
    result = run(env)
    assert result.returncode == 0
    assert "restart pypowerwall" in env["log"].read_text()


def test_docker_failure_is_not_reported_healthy(env):
    """docker inspect failing (daemon down, no container) must not read as healthy."""
    stub(env["bin"], "docker", "exit 1")
    result = run(env, "-debug")
    assert "is healthy" not in result.stdout
    assert "ERROR" in result.stdout
    assert result.returncode != 0


def test_enable_from_another_directory_uses_script_path(env):
    """The crontab entry must point at the script, not the caller's directory."""
    crontab = env["tmp"] / "crontab.txt"
    stub(env["bin"], "crontab", f'if [ "$1" = "-l" ]; then cat {crontab} 2>/dev/null; else cat > {crontab}; fi')
    elsewhere = env["tmp"] / "elsewhere"
    elsewhere.mkdir()
    result = run(env, "-enable", cwd=elsewhere, stdin="y\n")
    assert result.returncode == 0
    assert f'{env["install"]}/watchdog.sh' in crontab.read_text()
    # A second -enable recognises the existing entry
    assert "INSTALLED" in run(env, "-enable", cwd=elsewhere).stdout


def test_enable_with_cdpath_and_relative_path(env):
    """An exported CDPATH makes `cd` print the directory; the crontab entry must stay one line."""
    crontab = env["tmp"] / "crontab.txt"
    stub(env["bin"], "crontab", f'if [ "$1" = "-l" ]; then cat {crontab} 2>/dev/null; else cat > {crontab}; fi')
    result = subprocess.run(["/bin/bash", "Powerwall-Dashboard/watchdog.sh", "-enable"],
                            cwd=env["tmp"], env={**env["env"], "CDPATH": str(env["tmp"])},
                            input="y\n", capture_output=True, text=True)
    assert result.returncode == 0
    assert crontab.read_text().splitlines() == [
        f'*/5 * * * * /bin/bash {env["install"]}/watchdog.sh > /dev/null 2>&1']
