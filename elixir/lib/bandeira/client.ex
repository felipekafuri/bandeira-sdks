defmodule Bandeira.Client do
  @moduledoc """
  OTP client for Bandeira feature flags.
  """

  use GenServer

  alias Bandeira.Config
  alias Bandeira.Context
  alias Bandeira.Evaluator
  alias Bandeira.HTTPFlagsRepository

  @type state :: %{
          config: Config.t(),
          flags_by_name: map(),
          timer_ref: reference() | nil
        }

  @spec start_link(Config.t() | map() | keyword(), keyword()) :: GenServer.on_start()
  def start_link(config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  @spec is_enabled(GenServer.server(), String.t(), Context.t() | map() | nil) :: boolean()
  def is_enabled(client, name, context \\ nil) do
    GenServer.call(client, {:is_enabled, name, context})
  end

  @spec all_flags(GenServer.server()) :: %{optional(String.t()) => boolean()}
  def all_flags(client), do: GenServer.call(client, :all_flags)

  @spec load_flags(GenServer.server(), map()) :: :ok
  def load_flags(client, response), do: GenServer.call(client, {:load_flags, response})

  @spec close(GenServer.server()) :: :ok
  def close(client) do
    GenServer.stop(client, :normal)
  end

  @impl true
  def init(raw_config) do
    with {:ok, config} <- Config.new(raw_config),
         {:ok, flags_by_name} <- HTTPFlagsRepository.fetch_flags(config) do
      state = %{config: config, flags_by_name: flags_by_name, timer_ref: nil}
      {:ok, schedule_poll(state)}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:is_enabled, name, context}, _from, state) do
    flag = Map.get(state.flags_by_name, name)
    enabled = Evaluator.is_flag_enabled(flag, Context.normalize(context))
    {:reply, enabled, state}
  end

  def handle_call(:all_flags, _from, state) do
    flags =
      state.flags_by_name
      |> Enum.reduce(%{}, fn {name, flag}, acc ->
        Map.put(acc, name, flag.enabled == true)
      end)

    {:reply, flags, state}
  end

  def handle_call({:load_flags, response}, _from, state) do
    flags_by_name = Bandeira.FlagModels.parse_response(response)
    {:reply, :ok, %{state | flags_by_name: flags_by_name}}
  end

  @impl true
  def handle_info(:poll, state) do
    flags_by_name =
      case HTTPFlagsRepository.fetch_flags(state.config) do
        {:ok, flags} -> flags
        {:error, _reason} -> state.flags_by_name
      end

    new_state = %{state | flags_by_name: flags_by_name, timer_ref: nil}
    {:noreply, schedule_poll(new_state)}
  end

  defp schedule_poll(state) do
    poll_interval = state.config.poll_interval
    ref = Process.send_after(self(), :poll, poll_interval)
    %{state | timer_ref: ref}
  end
end
