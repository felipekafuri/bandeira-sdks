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
          timer_ref: reference() | nil,
          sse_pid: pid() | nil
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
      state = %{config: config, flags_by_name: flags_by_name, timer_ref: nil, sse_pid: nil}

      if config.streaming do
        {:ok, start_sse(state)}
      else
        {:ok, schedule_poll(state)}
      end
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

  def handle_info({:sse_flags, flags_by_name}, state) do
    {:noreply, %{state | flags_by_name: flags_by_name}}
  end

  def handle_info({:sse_down, _reason}, state) do
    {:noreply, schedule_sse_reconnect(state, 1_000)}
  end

  def handle_info({:reconnect_sse, backoff}, state) do
    parent = self()
    pid = spawn_link(fn -> sse_loop(state.config, parent, backoff) end)
    {:noreply, %{state | sse_pid: pid}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{sse_pid: pid} = state) do
    {:noreply, schedule_sse_reconnect(state, 1_000)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_poll(state) do
    poll_interval = state.config.poll_interval
    ref = Process.send_after(self(), :poll, poll_interval)
    %{state | timer_ref: ref}
  end

  defp start_sse(state) do
    parent = self()
    pid = spawn_link(fn -> sse_loop(state.config, parent, 1_000) end)
    %{state | sse_pid: pid}
  end

  defp schedule_sse_reconnect(state, backoff) do
    ref = Process.send_after(self(), {:reconnect_sse, backoff}, backoff)
    %{state | timer_ref: ref, sse_pid: nil}
  end

  defp sse_loop(config, parent, backoff) do
    url = String.trim_trailing(config.url, "/") <> "/api/v1/stream"

    headers = [
      {~c"Authorization", String.to_charlist("Bearer #{config.token}")},
      {~c"Accept", ~c"text/event-stream"}
    ]

    http_opts = [{:timeout, :infinity}, {:connect_timeout, 10_000}]
    opts = [{:sync, false}, {:stream, :self}]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, opts) do
      {:ok, request_id} ->
        sse_receive_loop(request_id, parent, "", "", [], backoff)

      {:error, _reason} ->
        send(parent, {:sse_down, :connect_failed})
    end
  end

  defp sse_receive_loop(request_id, parent, buf, event_type, data_lines, _backoff) do
    receive do
      {:http, {^request_id, :stream_start, _headers}} ->
        sse_receive_loop(request_id, parent, buf, event_type, data_lines, 1_000)

      {:http, {^request_id, :stream, chunk}} ->
        full = buf <> to_string(chunk)
        lines = String.split(full, "\n")
        # Last element might be incomplete
        {complete, [rest]} = Enum.split(lines, -1)

        {new_event_type, new_data_lines} =
          Enum.reduce(complete, {event_type, data_lines}, fn line, {evt, dlines} ->
            cond do
              String.starts_with?(line, ":") ->
                {evt, dlines}

              String.starts_with?(line, "event:") ->
                {String.trim(String.slice(line, 6..-1//1)), dlines}

              String.starts_with?(line, "data:") ->
                {evt, dlines ++ [String.trim(String.slice(line, 5..-1//1))]}

              line == "" ->
                if evt == "flags" and dlines != [] do
                  payload = Enum.join(dlines, "\n")

                  case Jason.decode(payload) do
                    {:ok, data} ->
                      flags = Bandeira.FlagModels.parse_response(data)
                      send(parent, {:sse_flags, flags})

                    _ ->
                      :ok
                  end
                end

                {"", []}

              true ->
                {evt, dlines}
            end
          end)

        sse_receive_loop(request_id, parent, rest, new_event_type, new_data_lines, 1_000)

      {:http, {^request_id, :stream_end, _headers}} ->
        send(parent, {:sse_down, :stream_ended})

      {:http, {^request_id, {:error, reason}}} ->
        send(parent, {:sse_down, reason})
    after
      60_000 ->
        :httpc.cancel_request(request_id)
        send(parent, {:sse_down, :timeout})
    end
  end
end
