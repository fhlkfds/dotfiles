#!/usr/bin/env python3
"""Run the CI shell steps against isolated Git repositories and audit fixtures."""
from pathlib import Path
import os
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github/workflows/ci.yml").read_text()


def step(name):
    body = WORKFLOW.split(f"      - name: {name}\n", 1)[1].split("\n      - ", 1)[0]
    if "        run: |\n" in body:
        lines = []
        for line in body.split("        run: |\n", 1)[1].splitlines():
            if line and not line.startswith("          "):
                break
            lines.append(line)
        return textwrap.dedent("\n".join(lines))
    return body.split("        run: ", 1)[1].splitlines()[0]


class CiWorkflowTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ci-workflow-test.")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=str(self.root / "gitconfig"),
                        GIT_CONFIG_NOSYSTEM="1", RUNNER_TEMP=str(self.root))
        self.run_command("git", "init", "-q")
        (self.repo / "fixture.py").write_text("print('fixture')\n")
        self.run_command("git", "add", ".")
        self.run_command("git", "-c", "user.name=Fixture", "-c",
                         "user.email=fixture@example.invalid", "commit", "-qm", "fixture")

    def run_command(self, *command, check=True):
        return subprocess.run(command, cwd=self.repo, env=self.env,
                              capture_output=True, text=True, check=check)

    def run_step(self, name):
        return self.run_command("bash", "-euo", "pipefail", "-c", step(name), check=False)

    def test_container_checkout_is_trusted_after_ownership_changes(self):
        self.env["GIT_TEST_ASSUME_DIFFERENT_OWNER"] = "1"
        self.assertNotEqual(self.run_command("git", "status", check=False).returncode, 0)
        result = self.run_step("Trust the container checkout path")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.run_command("git", "status", check=False).returncode, 0)

    def test_missing_base_creates_an_empty_tree_and_still_checks_sources(self):
        self.env["BASE_SHA"] = "missing-ci-base"
        result = self.run_step("Check syntax, changed shell scripts, and whitespace")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        (self.repo / "fixture.py").write_text("def broken syntax\n")
        result = self.run_step("Check syntax, changed shell scripts, and whitespace")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("::error file=fixture.py::", result.stdout)

    def test_package_audit_reports_unfixed_advisories_and_blocks_available_fixes(self):
        binary_dir = self.root / "bin"
        binary_dir.mkdir()
        audit = binary_dir / "arch-audit"
        audit.write_text('''#!/usr/bin/env bash
if [[ " $* " != *" --upgradable "* || ${AUDIT_FIX_AVAILABLE:-0} == 1 ]]; then
  printf 'fixture-package: CVE-fixture (High risk)\\n'
fi
''')
        audit.chmod(0o755)
        self.env["PATH"] = f"{binary_dir}:{self.env['PATH']}"
        result = self.run_step("Audit Arch packages for known vulnerabilities")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CVE-fixture", result.stdout)
        self.env["AUDIT_FIX_AVAILABLE"] = "1"
        result = self.run_step("Audit Arch packages for known vulnerabilities")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
