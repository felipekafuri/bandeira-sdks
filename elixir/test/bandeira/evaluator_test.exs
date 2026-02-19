defmodule Bandeira.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Bandeira.Context
  alias Bandeira.Evaluator
  alias Bandeira.FlagModels.{Constraint, Flag, Strategy}

  import Bandeira.TestFixtures

  test "enabled flag with no strategies returns true" do
    assert Evaluator.is_flag_enabled(flag!("simple-on"), nil)
  end

  test "disabled flag returns false" do
    refute Evaluator.is_flag_enabled(flag!("simple-off"), nil)
  end

  test "default strategy returns true" do
    assert Evaluator.is_flag_enabled(flag!("default-strategy"), nil)
  end

  test "userWithId matches listed user" do
    context = %Context{user_id: "user-42"}
    assert Evaluator.is_flag_enabled(flag!("user-targeting"), context)
  end

  test "userWithId rejects unlisted user" do
    context = %Context{user_id: "user-99"}
    refute Evaluator.is_flag_enabled(flag!("user-targeting"), context)
  end

  test "userWithId rejects without context" do
    refute Evaluator.is_flag_enabled(flag!("user-targeting"), nil)
  end

  test "userWithId handles newline-separated user IDs" do
    assert Evaluator.is_flag_enabled(flag!("user-targeting-newlines"), %Context{user_id: "user-42"})
    refute Evaluator.is_flag_enabled(flag!("user-targeting-newlines"), %Context{user_id: "user-99"})
  end

  test "gradualRollout 100 percent is always on" do
    assert Evaluator.is_flag_enabled(flag!("rollout-100"), %Context{user_id: "anyone"})
  end

  test "gradualRollout 0 percent is always off" do
    refute Evaluator.is_flag_enabled(flag!("rollout-0"), %Context{user_id: "anyone"})
  end

  test "gradualRollout with missing stickiness returns false" do
    refute Evaluator.is_flag_enabled(flag!("rollout-50"), nil)
  end

  test "gradualRollout session stickiness returns a boolean" do
    result = Evaluator.is_flag_enabled(flag!("rollout-session-stickiness"), %Context{session_id: "sess-123"})
    assert is_boolean(result)
  end

  test "remoteAddress exact match" do
    assert Evaluator.is_flag_enabled(flag!("ip-allowlist"), %Context{remote_address: "10.0.0.1"})
  end

  test "remoteAddress prefix match" do
    assert Evaluator.is_flag_enabled(flag!("ip-allowlist"), %Context{remote_address: "192.168.1.100"})
  end

  test "remoteAddress no match" do
    refute Evaluator.is_flag_enabled(flag!("ip-allowlist"), %Context{remote_address: "172.16.0.1"})
  end

  test "remoteAddress supports legacy IPs parameter key" do
    assert Evaluator.is_flag_enabled(flag!("ip-allowlist-legacy"), %Context{remote_address: "10.0.0.1"})
  end

  test "constraint IN matches" do
    context = %Context{properties: %{"companyId" => "2"}}
    assert Evaluator.is_flag_enabled(flag!("constraint-in"), context)
  end

  test "constraint IN rejects" do
    context = %Context{properties: %{"companyId" => "99"}}
    refute Evaluator.is_flag_enabled(flag!("constraint-in"), context)
  end

  test "constraint NOT_IN matches" do
    context = %Context{properties: %{"plan" => "enterprise"}}
    assert Evaluator.is_flag_enabled(flag!("constraint-not-in"), context)
  end

  test "constraint NOT_IN rejects" do
    context = %Context{properties: %{"plan" => "free"}}
    refute Evaluator.is_flag_enabled(flag!("constraint-not-in"), context)
  end

  test "inverted constraint" do
    free = %Context{properties: %{"plan" => "free"}}
    enterprise = %Context{properties: %{"plan" => "enterprise"}}

    refute Evaluator.is_flag_enabled(flag!("constraint-inverted"), free)
    assert Evaluator.is_flag_enabled(flag!("constraint-inverted"), enterprise)
  end

  test "case-insensitive constraint" do
    assert Evaluator.is_flag_enabled(flag!("constraint-case-insensitive"), %Context{properties: %{"country" => "brazil"}})
    assert Evaluator.is_flag_enabled(flag!("constraint-case-insensitive"), %Context{properties: %{"country" => "PORTUGAL"}})
    refute Evaluator.is_flag_enabled(flag!("constraint-case-insensitive"), %Context{properties: %{"country" => "spain"}})
  end

  test "STR_CONTAINS constraint" do
    assert Evaluator.is_flag_enabled(flag!("constraint-str-contains"), %Context{properties: %{"email" => "user@acme.com"}})
    refute Evaluator.is_flag_enabled(flag!("constraint-str-contains"), %Context{properties: %{"email" => "user@other.com"}})
  end

  test "STR_STARTS_WITH constraint" do
    assert Evaluator.is_flag_enabled(flag!("constraint-str-starts-with"), %Context{properties: %{"email" => "admin@acme.com"}})
    refute Evaluator.is_flag_enabled(flag!("constraint-str-starts-with"), %Context{properties: %{"email" => "user@acme.com"}})
  end

  test "STR_ENDS_WITH constraint" do
    assert Evaluator.is_flag_enabled(flag!("constraint-str-ends-with"), %Context{properties: %{"email" => "user@acme.com"}})
    refute Evaluator.is_flag_enabled(flag!("constraint-str-ends-with"), %Context{properties: %{"email" => "user@acme.io"}})
  end

  test "NUM_GTE constraint" do
    assert Evaluator.is_flag_enabled(flag!("constraint-num-gte"), %Context{properties: %{"age" => "21"}})
    assert Evaluator.is_flag_enabled(flag!("constraint-num-gte"), %Context{properties: %{"age" => "18"}})
    refute Evaluator.is_flag_enabled(flag!("constraint-num-gte"), %Context{properties: %{"age" => "16"}})
  end

  test "DATE_AFTER constraint" do
    assert Evaluator.is_flag_enabled(flag!("constraint-date-after"), %Context{properties: %{"signupDate" => "2026-06-15T00:00:00Z"}})
    refute Evaluator.is_flag_enabled(flag!("constraint-date-after"), %Context{properties: %{"signupDate" => "2025-06-15T00:00:00Z"}})
  end

  test "multi-strategy uses OR logic" do
    assert Evaluator.is_flag_enabled(flag!("multi-strategy"), %Context{user_id: "vip-1"})
  end

  test "constrained rollout passes when constraint matches" do
    context = %Context{user_id: "any-user", properties: %{"companyId" => "acme"}}
    assert Evaluator.is_flag_enabled(flag!("constrained-rollout"), context)
  end

  test "constrained rollout fails when constraint does not match" do
    context = %Context{user_id: "any-user", properties: %{"companyId" => "other"}}
    refute Evaluator.is_flag_enabled(flag!("constrained-rollout"), context)
  end

  test "unknown strategy fails open" do
    flag = %Flag{name: "unknown", enabled: true, strategies: [%Strategy{name: "someFutureStrategy"}]}
    assert Evaluator.is_flag_enabled(flag, %Context{})
  end

  test "unknown operator returns false" do
    flag = %Flag{
      name: "unknown-op",
      enabled: true,
      strategies: [
        %Strategy{
          name: "default",
          constraints: [%Constraint{context_name: "region", operator: "UNKNOWN", values: ["us"]}]
        }
      ]
    }

    refute Evaluator.is_flag_enabled(flag, %Context{properties: %{"region" => "us"}})
  end
end
