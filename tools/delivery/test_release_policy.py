"""Offline security regression tests for the public-release promotion gate."""
import unittest

from release_policy import APPROVAL_VARIABLES, ReleaseGateError, check_public_preview_approvals

SOURCE = "a" * 40


def approved(source: str = SOURCE) -> dict[str, str]:
    return {key: source for key in APPROVAL_VARIABLES}


class PublicReleaseGateTests(unittest.TestCase):
    def test_exact_source_with_all_attestations(self):
        self.assertIsNone(check_public_preview_approvals(SOURCE, approved()))

    def test_missing_every_individual_approval_rejected(self):
        for key in APPROVAL_VARIABLES:
            with self.subTest(key=key):
                values = approved()
                del values[key]
                with self.assertRaisesRegex(ReleaseGateError, key):
                    check_public_preview_approvals(SOURCE, values)

    def test_wrong_sha_in_each_approval_rejected(self):
        for key in APPROVAL_VARIABLES:
            with self.subTest(key=key):
                values = approved()
                values[key] = "b" * 40
                with self.assertRaisesRegex(ReleaseGateError, key):
                    check_public_preview_approvals(SOURCE, values)

    def test_approval_scope_is_exact_not_prefix_or_casefolded(self):
        for value in (SOURCE[:12], SOURCE.upper(), " " + SOURCE, SOURCE + " ", "", "true"):
            with self.subTest(value=value):
                values = approved()
                values[APPROVAL_VARIABLES[0]] = value
                with self.assertRaises(ReleaseGateError):
                    check_public_preview_approvals(SOURCE, values)

    def test_bad_source_shas_rejected(self):
        for source in ("", "main", "refs/heads/main", SOURCE[:12], SOURCE.upper(), SOURCE + "0", " " + SOURCE):
            with self.subTest(source=source):
                with self.assertRaises(ReleaseGateError):
                    check_public_preview_approvals(source, approved())

    def test_new_build_needs_fresh_fourfold_approval(self):
        with self.assertRaises(ReleaseGateError):
            check_public_preview_approvals("b" * 40, approved(SOURCE))


if __name__ == "__main__":
    unittest.main()
