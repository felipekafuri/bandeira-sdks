defmodule Bandeira.Context do
  @moduledoc "Runtime context used for strategy evaluation."

  @type t :: %__MODULE__{
          user_id: String.t(),
          session_id: String.t(),
          remote_address: String.t(),
          properties: %{optional(String.t()) => String.t()}
        }

  defstruct user_id: "",
            session_id: "",
            remote_address: "",
            properties: %{}

  @spec normalize(t() | map() | nil) :: t()
  def normalize(%__MODULE__{} = context), do: context
  def normalize(nil), do: %__MODULE__{}

  def normalize(map) when is_map(map) do
    %__MODULE__{
      user_id: get(map, :user_id, get(map, :userId, "")) |> to_string_safe(),
      session_id: get(map, :session_id, get(map, :sessionId, "")) |> to_string_safe(),
      remote_address: get(map, :remote_address, get(map, :remoteAddress, "")) |> to_string_safe(),
      properties: normalize_properties(get(map, :properties, %{}))
    }
  end

  def normalize(_), do: %__MODULE__{}

  defp normalize_properties(props) when is_map(props) do
    props
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), to_string_safe(value))
    end)
  end

  defp normalize_properties(_), do: %{}

  defp to_string_safe(nil), do: ""
  defp to_string_safe(value), do: to_string(value)

  defp get(map, key, default) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      is_atom(key) and Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> default
    end
  end
end
