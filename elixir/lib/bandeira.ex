defmodule Bandeira do
  @moduledoc """
  Official Elixir client SDK for Bandeira feature flags.

  The client polls Bandeira in the background, stores flags in memory,
  and evaluates strategies locally.
  """

  alias Bandeira.Client
  alias Bandeira.Config
  alias Bandeira.Context

  @doc "Starts a Bandeira client process."
  @spec start_link(Config.t() | map() | keyword(), keyword()) :: GenServer.on_start()
  def start_link(config, opts \\ []), do: Client.start_link(config, opts)

  @doc "Returns true if the given flag is enabled for the provided context."
  @spec is_enabled(GenServer.server(), String.t(), Context.t() | map() | nil) :: boolean()
  def is_enabled(client, name, context \\ nil), do: Client.is_enabled(client, name, context)

  @doc "Returns all known flags and their enabled state."
  @spec all_flags(GenServer.server()) :: %{optional(String.t()) => boolean()}
  def all_flags(client), do: Client.all_flags(client)

  @doc "Stops the Bandeira client process."
  @spec close(GenServer.server()) :: :ok
  def close(client), do: Client.close(client)
end
