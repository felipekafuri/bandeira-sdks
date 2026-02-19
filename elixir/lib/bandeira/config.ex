defmodule Bandeira.Config do
  @moduledoc "Configuration for a Bandeira client."

  @type http_client_fun :: (String.t(), [{String.t(), String.t()}] ->
                              {:ok, non_neg_integer(), binary()} | {:error, term()})

  @type t :: %__MODULE__{
          url: String.t(),
          token: String.t(),
          poll_interval: pos_integer(),
          http_client: http_client_fun() | nil
        }

  defstruct url: "",
            token: "",
            poll_interval: 15_000,
            http_client: nil

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(%__MODULE__{} = cfg), do: validate(cfg)

  def new(opts) when is_list(opts) do
    opts
    |> Enum.into(%{})
    |> new()
  end

  def new(map) when is_map(map) do
    cfg = %__MODULE__{
      url: get(map, :url, ""),
      token: get(map, :token, ""),
      poll_interval: get(map, :poll_interval, 15_000),
      http_client: get(map, :http_client, nil)
    }

    validate(cfg)
  end

  def new(_), do: {:error, "bandeira: config must be a map, keyword list, or %Bandeira.Config{}"}

  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = cfg) do
    cond do
      String.trim(to_string(cfg.url)) == "" ->
        {:error, "bandeira: url is required"}

      String.trim(to_string(cfg.token)) == "" ->
        {:error, "bandeira: token is required"}

      not is_integer(cfg.poll_interval) or cfg.poll_interval <= 0 ->
        {:error, "bandeira: poll_interval must be a positive integer in milliseconds"}

      not is_nil(cfg.http_client) and not is_function(cfg.http_client, 2) ->
        {:error, "bandeira: http_client must be a function of arity 2"}

      true ->
        {:ok, %{cfg | url: String.trim(cfg.url), token: String.trim(cfg.token)}}
    end
  end

  defp get(map, key, default) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      is_atom(key) and Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> default
    end
  end
end
