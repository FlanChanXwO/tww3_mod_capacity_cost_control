import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import ensure_labels
import issue_triage
import record_release


class CiToolsTests(unittest.TestCase):
    def test_label_initialization_uses_repository_config(self) -> None:
        definitions = json.loads((ensure_labels.ROOT / ".github/labels.json").read_text(encoding="utf-8"))
        with patch.object(ensure_labels.subprocess, "run") as run:
            ensure_labels.ensure_labels()
        self.assertEqual(len(run.call_args_list), len(definitions))
        for call, (name, values) in zip(run.call_args_list, definitions.items()):
            self.assertEqual(call.args[0], ["gh", "label", "create", name, "--force",
                "--color", values["color"], "--description", values["description"]])
            self.assertTrue(call.kwargs["check"])

    def test_issue_labels_assignment_and_repeated_runs(self) -> None:
        author = json.loads((issue_triage.ROOT / "data/project.json").read_text(encoding="utf-8"))["author"]
        cases = (
            ("[Bug] price", [], [], ["--add-label", "bug", "--add-assignee", author]),
            ("[Feature] option", [], ["someone"], ["--add-label", "enhancement"]),
            ("[Bug] price", ["bug", "docs"], [], ["--add-assignee", author]),
            ("Other", [], [], ["--add-assignee", author]),
            ("[Feature] done", ["enhancement"], ["someone"], []),
        )
        for title, labels, assignees, expected in cases:
            with self.subTest(title=title, assignees=assignees):
                issue = {"title": title, "labels": [{"name": name} for name in labels], "assignees": assignees}

                def github(command, **kwargs):
                    if command[2] == "view":
                        return subprocess.CompletedProcess(command, 0, stdout=json.dumps(issue))
                    if "--add-label" in command:
                        issue["labels"].append({"name": command[command.index("--add-label") + 1]})
                    if "--add-assignee" in command:
                        issue["assignees"].append(command[command.index("--add-assignee") + 1])
                    return subprocess.CompletedProcess(command, 0)

                with patch.object(issue_triage.subprocess, "run", side_effect=github) as run:
                    issue_triage.triage_issue(7, author)
                    edits = [call.args[0] for call in run.call_args_list if call.args[0][2] == "edit"]
                    self.assertEqual(edits, [["gh", "issue", "edit", "7", *expected]] if expected else [])
                    run.reset_mock()
                    issue_triage.triage_issue(7, author)
                    self.assertEqual(run.call_count, 1, "repeated runs should only read current state")
                for label in labels:
                    self.assertIn({"name": label}, issue["labels"])

    def test_issue_failure_is_reported(self) -> None:
        with patch.object(issue_triage.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "gh")):
            with self.assertRaises(subprocess.CalledProcessError):
                issue_triage.triage_issue(7, "maintainer")

    def test_release_validation_and_notes(self) -> None:
        with patch.object(record_release.subprocess, "run") as run:
            for values in (("main", "123", "a" * 64), ("v1.0.0", "abc", "a" * 64), ("v1.0.0", "123", "bad")):
                with self.subTest(values=values), self.assertRaises(ValueError):
                    record_release.record_release(*values)
            run.assert_not_called()

        def github(command, **kwargs):
            self.assertEqual(command[:7], ["gh", "release", "create", "v1.0.0", "--verify-tag", "--title", "v1.0.0"])
            notes = Path(command[-1]).read_text(encoding="utf-8")
            self.assertEqual(notes, "Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=123\nPack SHA256: " + "a" * 64 + "\n")

        with patch.object(record_release.subprocess, "run", side_effect=github):
            record_release.record_release("v1.0.0", "123", "a" * 64)


if __name__ == "__main__":
    unittest.main()
