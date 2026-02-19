"""Tests for the Bandeira Python SDK using shared test fixtures."""

import json
import unittest
from pathlib import Path

from bandeira import BandeiraClient, Config, Context

FIXTURES = json.loads(
    (Path(__file__).parent.parent.parent / "testdata" / "flags.json").read_text()
)


def create_client() -> BandeiraClient:
    client = BandeiraClient(Config(url="http://localhost:9999", token="test-token"))
    client.load_flags(FIXTURES)
    return client


class TestBasicToggles(unittest.TestCase):
    def test_enabled_flag_no_strategies(self):
        c = create_client()
        self.assertTrue(c.is_enabled("simple-on"))

    def test_disabled_flag(self):
        c = create_client()
        self.assertFalse(c.is_enabled("simple-off"))

    def test_unknown_flag(self):
        c = create_client()
        self.assertFalse(c.is_enabled("nonexistent"))


class TestDefaultStrategy(unittest.TestCase):
    def test_returns_true(self):
        c = create_client()
        self.assertTrue(c.is_enabled("default-strategy"))


class TestUserWithId(unittest.TestCase):
    def test_matches_listed_user(self):
        c = create_client()
        self.assertTrue(c.is_enabled("user-targeting", Context(user_id="user-42")))

    def test_rejects_unlisted_user(self):
        c = create_client()
        self.assertFalse(c.is_enabled("user-targeting", Context(user_id="user-99")))

    def test_rejects_no_context(self):
        c = create_client()
        self.assertFalse(c.is_enabled("user-targeting"))

    def test_newline_separated(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled("user-targeting-newlines", Context(user_id="user-42"))
        )
        self.assertFalse(
            c.is_enabled("user-targeting-newlines", Context(user_id="user-99"))
        )


class TestGradualRollout(unittest.TestCase):
    def test_100_percent(self):
        c = create_client()
        self.assertTrue(c.is_enabled("rollout-100", Context(user_id="anyone")))

    def test_0_percent(self):
        c = create_client()
        self.assertFalse(c.is_enabled("rollout-0", Context(user_id="anyone")))

    def test_no_stickiness(self):
        c = create_client()
        self.assertFalse(c.is_enabled("rollout-50"))

    def test_session_stickiness(self):
        c = create_client()
        result = c.is_enabled(
            "rollout-session-stickiness", Context(session_id="sess-123")
        )
        self.assertIsInstance(result, bool)


class TestRemoteAddress(unittest.TestCase):
    def test_exact_match(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled("ip-allowlist", Context(remote_address="10.0.0.1"))
        )

    def test_prefix_match(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled("ip-allowlist", Context(remote_address="192.168.1.100"))
        )

    def test_no_match(self):
        c = create_client()
        self.assertFalse(
            c.is_enabled("ip-allowlist", Context(remote_address="172.16.0.1"))
        )

    def test_legacy_ips_key(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled("ip-allowlist-legacy", Context(remote_address="10.0.0.1"))
        )


class TestConstraints(unittest.TestCase):
    def test_in_matches(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled(
                "constraint-in", Context(properties={"companyId": "2"})
            )
        )

    def test_in_rejects(self):
        c = create_client()
        self.assertFalse(
            c.is_enabled(
                "constraint-in", Context(properties={"companyId": "99"})
            )
        )

    def test_not_in_matches(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled(
                "constraint-not-in", Context(properties={"plan": "enterprise"})
            )
        )

    def test_not_in_rejects(self):
        c = create_client()
        self.assertFalse(
            c.is_enabled(
                "constraint-not-in", Context(properties={"plan": "free"})
            )
        )

    def test_inverted(self):
        c = create_client()
        self.assertFalse(
            c.is_enabled(
                "constraint-inverted", Context(properties={"plan": "free"})
            )
        )
        self.assertTrue(
            c.is_enabled(
                "constraint-inverted",
                Context(properties={"plan": "enterprise"}),
            )
        )

    def test_case_insensitive(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled(
                "constraint-case-insensitive",
                Context(properties={"country": "brazil"}),
            )
        )
        self.assertTrue(
            c.is_enabled(
                "constraint-case-insensitive",
                Context(properties={"country": "PORTUGAL"}),
            )
        )
        self.assertFalse(
            c.is_enabled(
                "constraint-case-insensitive",
                Context(properties={"country": "spain"}),
            )
        )

    def test_str_contains(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled(
                "constraint-str-contains",
                Context(properties={"email": "user@acme.com"}),
            )
        )
        self.assertFalse(
            c.is_enabled(
                "constraint-str-contains",
                Context(properties={"email": "user@other.com"}),
            )
        )

    def test_str_starts_with(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled(
                "constraint-str-starts-with",
                Context(properties={"email": "admin@acme.com"}),
            )
        )
        self.assertFalse(
            c.is_enabled(
                "constraint-str-starts-with",
                Context(properties={"email": "user@acme.com"}),
            )
        )

    def test_str_ends_with(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled(
                "constraint-str-ends-with",
                Context(properties={"email": "user@acme.com"}),
            )
        )
        self.assertFalse(
            c.is_enabled(
                "constraint-str-ends-with",
                Context(properties={"email": "user@acme.io"}),
            )
        )

    def test_num_gte(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled("constraint-num-gte", Context(properties={"age": "21"}))
        )
        self.assertTrue(
            c.is_enabled("constraint-num-gte", Context(properties={"age": "18"}))
        )
        self.assertFalse(
            c.is_enabled("constraint-num-gte", Context(properties={"age": "16"}))
        )

    def test_date_after(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled(
                "constraint-date-after",
                Context(properties={"signupDate": "2026-06-15T00:00:00Z"}),
            )
        )
        self.assertFalse(
            c.is_enabled(
                "constraint-date-after",
                Context(properties={"signupDate": "2025-06-15T00:00:00Z"}),
            )
        )


class TestMultiStrategy(unittest.TestCase):
    def test_vip_matches_first(self):
        c = create_client()
        self.assertTrue(c.is_enabled("multi-strategy", Context(user_id="vip-1")))


class TestConstrainedRollout(unittest.TestCase):
    def test_passes_with_matching_constraint(self):
        c = create_client()
        self.assertTrue(
            c.is_enabled(
                "constrained-rollout",
                Context(user_id="any-user", properties={"companyId": "acme"}),
            )
        )

    def test_fails_without_matching_constraint(self):
        c = create_client()
        self.assertFalse(
            c.is_enabled(
                "constrained-rollout",
                Context(user_id="any-user", properties={"companyId": "other"}),
            )
        )


class TestAllFlags(unittest.TestCase):
    def test_returns_all(self):
        c = create_client()
        flags = c.all_flags()
        self.assertTrue(flags["simple-on"])
        self.assertFalse(flags["simple-off"])


class TestValidation(unittest.TestCase):
    def test_missing_url(self):
        with self.assertRaises(ValueError):
            BandeiraClient(Config(url="", token="test"))

    def test_missing_token(self):
        with self.assertRaises(ValueError):
            BandeiraClient(Config(url="http://localhost", token=""))


if __name__ == "__main__":
    unittest.main()
