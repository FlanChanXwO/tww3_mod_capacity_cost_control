import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from check_pr_template import CHECKS, validate

ROOT = Path(__file__).resolve().parents[3]


def completed(verification="运行验证命令通过"):
    return ("## 变更点 / Changes\n调整模块路径\n"
            f"## 验证步骤 / Verification\n{verification}\n"
            "## 检查清单 / Checklist\n" + "\n".join(f"- [x] {item}" for item in CHECKS))


class PrTemplateTests(unittest.TestCase):
    def test_empty_or_incomplete_descriptions_fail(self) -> None:
        template = (ROOT / ".github/pull_request_template.md").read_text(encoding="utf-8")
        for body in (None, template, "<!-- " + completed() + " -->",
                     completed().replace("## 验证步骤 / Verification", "## Other"),
                     completed().replace("[x]", "[ ]")):
            with self.subTest(body=body):
                self.assertTrue(validate(body))

    def test_completed_or_reason_for_no_test_passes(self) -> None:
        self.assertEqual(validate(completed()), [])
        self.assertEqual(validate(completed("未测试：仅修改文档")), [])

    def test_code_blocks_cannot_supply_headings_or_checks(self) -> None:
        for fence in ("```", "~~~~"):
            self.assertTrue(validate(f"{fence}\n{completed()}\n{fence}"))
            body = completed().split("## 检查清单 / Checklist")[0]
            body += "## 检查清单 / Checklist\n" + fence + "\n"
            body += "\n".join(f"- [x] {item}" for item in CHECKS) + "\n" + fence
            self.assertTrue(validate(body))


if __name__ == "__main__":
    unittest.main()
