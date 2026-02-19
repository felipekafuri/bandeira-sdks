defmodule Bandeira.Evaluator do
  @moduledoc false

  import Bitwise

  alias Bandeira.Context
  alias Bandeira.FlagModels.{Constraint, Flag, Strategy}

  @spec is_flag_enabled(Flag.t() | nil, Context.t() | map() | nil) :: boolean()
  def is_flag_enabled(nil, _), do: false

  def is_flag_enabled(%Flag{enabled: false}, _), do: false

  def is_flag_enabled(%Flag{enabled: true, strategies: []}, _), do: true

  def is_flag_enabled(%Flag{} = flag, context) do
    eval_context = Context.normalize(context)

    Enum.any?(flag.strategies, fn strategy ->
      evaluate_strategy(strategy, eval_context)
    end)
  end

  @spec evaluate_strategy(Strategy.t(), Context.t()) :: boolean()
  def evaluate_strategy(%Strategy{} = strategy, %Context{} = context) do
    constraints_pass = Enum.all?(strategy.constraints, &evaluate_constraint(&1, context))

    if constraints_pass do
      case strategy.name do
        "default" -> true
        "userWithId" -> eval_user_with_id(strategy, context)
        "gradualRollout" -> eval_gradual_rollout(strategy, context)
        "remoteAddress" -> eval_remote_address(strategy, context)
        _ -> true
      end
    else
      false
    end
  end

  @spec evaluate_constraint(Constraint.t(), Context.t()) :: boolean()
  def evaluate_constraint(%Constraint{} = constraint, %Context{} = context) do
    context_value = context_value(constraint.context_name, context)

    result =
      eval_operator(
        constraint.operator,
        context_value,
        constraint.values,
        constraint.case_insensitive
      )

    if constraint.inverted, do: not result, else: result
  end

  @spec split_multi(String.t()) :: [String.t()]
  def split_multi(value) when is_binary(value) do
    value
    |> String.replace("\r\n", ",")
    |> String.replace("\n", ",")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def split_multi(_), do: []

  @spec normalized_hash(String.t()) :: non_neg_integer()
  def normalized_hash(value) when is_binary(value) do
    value
    |> :unicode.characters_to_binary()
    |> :binary.bin_to_list()
    |> Enum.reduce(0x811C9DC5, fn byte, hash ->
      (hash ^^^ byte) * 0x01000193 &&& 0xFFFFFFFF
    end)
    |> rem(100)
  end

  def normalized_hash(_), do: 0

  defp eval_user_with_id(%Strategy{} = strategy, %Context{} = context) do
    case get(strategy.parameters, "userIds") do
      user_ids when is_binary(user_ids) -> context.user_id in split_multi(user_ids)
      _ -> false
    end
  end

  defp eval_gradual_rollout(%Strategy{} = strategy, %Context{} = context) do
    with {:ok, rollout} <- parse_rollout(get(strategy.parameters, "rollout")) do
      cond do
        rollout >= 100 ->
          true

        rollout <= 0 ->
          false

        true ->
          stickiness = get(strategy.parameters, "stickiness")

          stickiness_key =
            if is_binary(stickiness) and stickiness != "" do
              stickiness
            else
              "userId"
            end

          stickiness_value =
            case stickiness_key do
              "userId" -> context.user_id
              "sessionId" -> context.session_id
              custom -> Map.get(context.properties, custom, "")
            end

          if stickiness_value == "" do
            false
          else
            group_id = get(strategy.parameters, "groupId")
            group_id_value = if is_binary(group_id), do: group_id, else: ""
            normalized_hash(stickiness_value <> group_id_value) < rollout
          end
      end
    else
      _ -> false
    end
  end

  defp eval_remote_address(%Strategy{} = strategy, %Context{} = context) do
    raw_ips =
      case get(strategy.parameters, "ips") do
        value when is_binary(value) -> value
        _ -> get(strategy.parameters, "IPs")
      end

    if is_binary(raw_ips) do
      address = context.remote_address

      Enum.any?(split_multi(raw_ips), fn entry ->
        entry == address or
          (String.ends_with?(entry, ".") and String.starts_with?(address, entry))
      end)
    else
      false
    end
  end

  defp context_value("userId", %Context{} = context), do: context.user_id
  defp context_value("sessionId", %Context{} = context), do: context.session_id
  defp context_value("remoteAddress", %Context{} = context), do: context.remote_address
  defp context_value(name, %Context{} = context), do: Map.get(context.properties, name, "")

  defp eval_operator(operator, context_value, values, case_insensitive) do
    cv = normalize(context_value, case_insensitive)

    case operator do
      "IN" ->
        Enum.any?(values, &(cv == normalize(&1, case_insensitive)))

      "NOT_IN" ->
        Enum.all?(values, &(cv != normalize(&1, case_insensitive)))

      "STR_CONTAINS" ->
        Enum.any?(values, &String.contains?(cv, normalize(&1, case_insensitive)))

      "STR_STARTS_WITH" ->
        Enum.any?(values, &String.starts_with?(cv, normalize(&1, case_insensitive)))

      "STR_ENDS_WITH" ->
        Enum.any?(values, &String.ends_with?(cv, normalize(&1, case_insensitive)))

      "NUM_EQ" ->
        compare_numeric(cv, values, &Kernel.==/2)

      "NUM_GT" ->
        compare_numeric(cv, values, &Kernel.>/2)

      "NUM_GTE" ->
        compare_numeric(cv, values, &Kernel.>=/2)

      "NUM_LT" ->
        compare_numeric(cv, values, &Kernel.</2)

      "NUM_LTE" ->
        compare_numeric(cv, values, &Kernel.<=/2)

      "DATE_AFTER" ->
        compare_datetime(cv, values, fn value, target ->
          DateTime.compare(value, target) == :gt
        end)

      "DATE_BEFORE" ->
        compare_datetime(cv, values, fn value, target ->
          DateTime.compare(value, target) == :lt
        end)

      _ ->
        false
    end
  end

  defp compare_numeric(cv, values, comparator) do
    with {:ok, value} <- parse_float(cv) do
      Enum.any?(values, fn raw_target ->
        case parse_float(raw_target) do
          {:ok, target} -> comparator.(value, target)
          _ -> false
        end
      end)
    else
      _ -> false
    end
  end

  defp compare_datetime(cv, values, comparator) do
    with {:ok, value} <- parse_datetime(cv) do
      Enum.any?(values, fn raw_target ->
        case parse_datetime(raw_target) do
          {:ok, target} -> comparator.(value, target)
          _ -> false
        end
      end)
    else
      _ -> false
    end
  end

  defp parse_rollout(raw) when is_integer(raw), do: {:ok, raw}
  defp parse_rollout(raw) when is_float(raw), do: {:ok, trunc(raw)}

  defp parse_rollout(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {rollout, ""} -> {:ok, rollout}
      _ -> :error
    end
  end

  defp parse_rollout(_), do: :error

  defp parse_float(value) when is_number(value), do: {:ok, value * 1.0}

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parse_float(_), do: :error

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp parse_datetime(_), do: :error

  defp normalize(value, true), do: value |> to_string() |> String.downcase()
  defp normalize(value, false), do: to_string(value)

  defp get(parameters, key) when is_map(parameters) do
    cond do
      Map.has_key?(parameters, key) ->
        Map.get(parameters, key)

      is_binary(key) ->
        Enum.find_value(parameters, fn
          {atom_key, value} when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: value, else: nil

          _ ->
            nil
        end)

      true ->
        nil
    end
  end

  defp get(_parameters, _key), do: nil
end
