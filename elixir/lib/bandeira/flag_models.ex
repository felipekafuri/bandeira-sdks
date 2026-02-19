defmodule Bandeira.FlagModels do
  @moduledoc false

  defmodule Flag do
    @moduledoc false
    defstruct name: "", enabled: false, strategies: []

    @type t :: %__MODULE__{
            name: String.t(),
            enabled: boolean(),
            strategies: [Bandeira.FlagModels.Strategy.t()]
          }
  end

  defmodule Strategy do
    @moduledoc false
    defstruct name: "", parameters: %{}, constraints: []

    @type t :: %__MODULE__{
            name: String.t(),
            parameters: map(),
            constraints: [Bandeira.FlagModels.Constraint.t()]
          }
  end

  defmodule Constraint do
    @moduledoc false
    defstruct context_name: "", operator: "", values: [], inverted: false, case_insensitive: false

    @type t :: %__MODULE__{
            context_name: String.t(),
            operator: String.t(),
            values: [String.t()],
            inverted: boolean(),
            case_insensitive: boolean()
          }
  end

  alias __MODULE__.{Constraint, Flag, Strategy}

  @spec parse_response(map()) :: %{optional(String.t()) => Flag.t()}
  def parse_response(data) when is_map(data) do
    data
    |> get(:flags, [])
    |> case do
      flags when is_list(flags) ->
        Enum.reduce(flags, %{}, fn raw, acc ->
          flag = to_flag(raw)

          if flag.name == "" do
            acc
          else
            Map.put(acc, flag.name, flag)
          end
        end)

      _ ->
        %{}
    end
  end

  def parse_response(_), do: %{}

  @spec to_flag(map()) :: Flag.t()
  def to_flag(raw) when is_map(raw) do
    %Flag{
      name: get(raw, :name, "") |> to_string_safe(),
      enabled: get(raw, :enabled, false) == true,
      strategies: to_strategies(get(raw, :strategies, []))
    }
  end

  def to_flag(_), do: %Flag{}

  defp to_strategies(strategies) when is_list(strategies) do
    Enum.map(strategies, &to_strategy/1)
  end

  defp to_strategies(_), do: []

  defp to_strategy(raw) when is_map(raw) do
    %Strategy{
      name: get(raw, :name, "") |> to_string_safe(),
      parameters: to_parameters(get(raw, :parameters, %{})),
      constraints: to_constraints(get(raw, :constraints, []))
    }
  end

  defp to_strategy(_), do: %Strategy{}

  defp to_parameters(parameters) when is_map(parameters), do: parameters
  defp to_parameters(_), do: %{}

  defp to_constraints(constraints) when is_list(constraints) do
    Enum.map(constraints, &to_constraint/1)
  end

  defp to_constraints(_), do: []

  defp to_constraint(raw) when is_map(raw) do
    %Constraint{
      context_name: get(raw, :context_name, "") |> to_string_safe(),
      operator: get(raw, :operator, "") |> to_string_safe(),
      values: to_values(get(raw, :values, [])),
      inverted: get(raw, :inverted, false) == true,
      case_insensitive: get(raw, :case_insensitive, false) == true
    }
  end

  defp to_constraint(_), do: %Constraint{}

  defp to_values(values) when is_list(values), do: Enum.map(values, &to_string_safe/1)
  defp to_values(_), do: []

  defp get(map, key, default) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      is_atom(key) and Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> default
    end
  end

  defp to_string_safe(nil), do: ""
  defp to_string_safe(value), do: to_string(value)
end
