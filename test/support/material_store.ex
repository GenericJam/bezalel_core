defmodule Bezalel.Test.MaterialStore do
  @moduledoc """
  A `Bezalel.Materials.Store` in memory for tests, kept per owner (the
  ctx's session) as a host serving several users keeps it: another
  session's materials aren't there, even with the same bytes.
  `install/0` starts it and configures it, restoring the config on exit.
  """
  @behaviour Bezalel.Materials.Store

  use Agent

  import ExUnit.Callbacks, only: [start_supervised!: 1, on_exit: 1]

  def start_link(_opts), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @doc "Starts the store and makes `module` (this one by default) `:bezalel_core, :materials`."
  def install(module \\ __MODULE__) do
    start_supervised!(__MODULE__)
    previous = Application.fetch_env(:bezalel_core, :materials)
    Application.put_env(:bezalel_core, :materials, module)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:bezalel_core, :materials, value)
        :error -> Application.delete_env(:bezalel_core, :materials)
      end
    end)
  end

  @impl true
  def put(material, bytes, ctx) do
    key = {ctx[:session_id], material.id}

    Agent.get_and_update(__MODULE__, fn kept ->
      case Map.fetch(kept, key) do
        {:ok, {existing, bytes}} ->
          merged = Bezalel.Materials.merge(existing, material)
          {{:ok, merged}, Map.put(kept, key, {merged, bytes})}

        :error ->
          {{:ok, material}, Map.put(kept, key, {material, bytes})}
      end
    end)
  end

  @impl true
  def fetch(id, ctx) do
    case Agent.get(__MODULE__, &Map.get(&1, {ctx[:session_id], id})) do
      {material, _bytes} -> {:ok, material}
      nil -> :error
    end
  end

  @impl true
  def read(material, ctx) do
    case Agent.get(__MODULE__, &Map.get(&1, {ctx[:session_id], material.id})) do
      {_material, bytes} -> {:ok, bytes}
      nil -> {:error, :enoent}
    end
  end

  @impl true
  def derivatives(id, ctx) do
    session = ctx[:session_id]

    for {{^session, _id}, {m, _bytes}} <- Agent.get(__MODULE__, & &1), id in m.derived_from, do: m
  end
end
