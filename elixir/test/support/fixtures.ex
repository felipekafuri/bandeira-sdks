defmodule Bandeira.TestFixtures do
  @moduledoc false

  alias Bandeira.FlagModels

  @fixtures_path Path.expand("../../../testdata/flags.json", __DIR__)

  def fixture_payload do
    @fixtures_path
    |> File.read!()
    |> Jason.decode!()
  end

  def flags_by_name do
    fixture_payload()
    |> FlagModels.parse_response()
  end

  def flag!(name) do
    flags_by_name()
    |> Map.fetch!(name)
  end
end
