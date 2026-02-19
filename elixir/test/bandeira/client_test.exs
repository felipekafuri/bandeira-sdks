defmodule Bandeira.ClientTest do
  use ExUnit.Case

  alias Bandeira.Client
  alias Bandeira.Config
  alias Bandeira.Context

  import Bandeira.TestFixtures

  test "start_link performs initial fetch and includes authorization header" do
    test_pid = self()
    payload = Jason.encode!(fixture_payload())

    http_fun = fn url, headers ->
      send(test_pid, {:request, url, headers})
      {:ok, 200, payload}
    end

    config = %Config{
      url: "http://localhost:9999/",
      token: "test-token",
      poll_interval: 60_000,
      http_client: http_fun
    }

    {:ok, pid} = Client.start_link(config)
    on_exit(fn -> Client.close(pid) end)

    assert_receive {:request, "http://localhost:9999/api/v1/flags", headers}
    assert {"authorization", "Bearer test-token"} in headers
    assert Client.is_enabled(pid, "simple-on", %Context{})
  end

  test "start_link fails fast when initial request is unauthorized" do
    config = %Config{
      url: "http://localhost:9999",
      token: "bad-token",
      poll_interval: 60_000,
      http_client: fn _url, _headers -> {:ok, 401, "unauthorized"} end
    }

    assert {:error, reason} = Client.start_link(config)
    assert to_string(reason) =~ "unexpected status 401"
  end

  test "all_flags returns enabled snapshot" do
    payload = Jason.encode!(fixture_payload())

    config = %Config{
      url: "http://localhost:9999",
      token: "test-token",
      poll_interval: 60_000,
      http_client: fn _url, _headers -> {:ok, 200, payload} end
    }

    {:ok, pid} = Client.start_link(config)
    on_exit(fn -> Client.close(pid) end)

    flags = Client.all_flags(pid)
    assert flags["simple-on"] == true
    assert flags["simple-off"] == false
  end

  test "load_flags allows direct fixture injection" do
    payload = Jason.encode!(%{"flags" => []})

    config = %Config{
      url: "http://localhost:9999",
      token: "test-token",
      poll_interval: 60_000,
      http_client: fn _url, _headers -> {:ok, 200, payload} end
    }

    {:ok, pid} = Client.start_link(config)
    on_exit(fn -> Client.close(pid) end)

    response = %{
      "flags" => [
        %{"name" => "manual-flag", "enabled" => true, "strategies" => []}
      ]
    }

    assert :ok == Client.load_flags(pid, response)
    assert Client.is_enabled(pid, "manual-flag", nil)
  end

  test "polling keeps last known cache on failures" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    payload = Jason.encode!(fixture_payload())

    http_fun = fn _url, _headers ->
      attempt =
        Agent.get_and_update(counter, fn current ->
          {current, current + 1}
        end)

      if attempt == 0 do
        {:ok, 200, payload}
      else
        {:ok, 500, "temporary failure"}
      end
    end

    config = %Config{
      url: "http://localhost:9999",
      token: "test-token",
      poll_interval: 5,
      http_client: http_fun
    }

    {:ok, pid} = Client.start_link(config)

    on_exit(fn ->
      Client.close(pid)
      Agent.stop(counter)
    end)

    assert Client.is_enabled(pid, "simple-on", nil)
    Process.sleep(30)
    assert Client.is_enabled(pid, "simple-on", nil)
  end

  test "validation errors for missing url and token" do
    assert {:error, reason1} = Client.start_link(%Config{url: "", token: "x"})
    assert to_string(reason1) =~ "url is required"

    assert {:error, reason2} = Client.start_link(%Config{url: "http://localhost", token: ""})
    assert to_string(reason2) =~ "token is required"
  end
end
