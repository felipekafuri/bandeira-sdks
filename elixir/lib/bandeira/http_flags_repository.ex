defmodule Bandeira.HTTPFlagsRepository do
  @moduledoc false

  alias Bandeira.Config
  alias Bandeira.FlagModels

  @spec fetch_flags(Config.t()) ::
          {:ok, %{optional(String.t()) => Bandeira.FlagModels.Flag.t()}} | {:error, String.t()}
  def fetch_flags(%Config{} = config) do
    url = normalized_url(config.url) <> "/api/v1/flags"
    headers = [{"authorization", "Bearer " <> config.token}]

    with {:ok, status, body} <- request(config, url, headers),
         :ok <- ensure_ok(status, body),
         {:ok, decoded} <- decode_json(body) do
      {:ok, FlagModels.parse_response(decoded)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(%Config{http_client: fun}, url, headers) when is_function(fun, 2) do
    fun.(url, headers)
  rescue
    error -> {:error, "request failed: #{Exception.message(error)}"}
  end

  defp request(_config, url, headers), do: default_http_get(url, headers)

  @doc false
  @spec default_http_get(String.t(), [{String.t(), String.t()}]) ::
          {:ok, non_neg_integer(), binary()} | {:error, String.t()}
  def default_http_get(url, headers) do
    _ = :inets.start()
    _ = :ssl.start()

    req_headers =
      Enum.map(headers, fn {name, value} ->
        {String.to_charlist(name), String.to_charlist(value)}
      end)

    request = {String.to_charlist(url), req_headers}

    case :httpc.request(:get, request, [timeout: 10_000], body_format: :binary) do
      {:ok, {{_http_version, status, _reason}, _resp_headers, body}} ->
        {:ok, status, IO.iodata_to_binary(body)}

      {:error, reason} ->
        {:error, "request failed: #{inspect(reason)}"}
    end
  end

  defp ensure_ok(200, _body), do: :ok

  defp ensure_ok(status, body) do
    {:error, "unexpected status #{status}: #{body}"}
  end

  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, error} -> {:error, "failed to decode response: #{Exception.message(error)}"}
    end
  end

  defp normalized_url(url) do
    String.replace(to_string(url), ~r{/+$}, "")
  end
end
