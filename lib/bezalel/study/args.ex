defmodule Bezalel.Study.Args do
  @moduledoc """
  Reading a study tool's JSON arguments (string keys) the way
  studybible-mcp's handlers read theirs: absent and null are the default,
  references are trimmed and single-chapter citations expanded ("Jude 3"
  is "Jude 1:3", as its `call_tool` does for every reference argument).
  """

  alias Bezalel.Study.Reference

  @doc "A string argument, trimmed; \"\" when absent, null or not a string."
  @spec string(map(), String.t()) :: String.t()
  def string(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) -> String.trim(value)
      _ -> ""
    end
  end

  @doc "A string argument, or nil when absent, null, empty or not a string."
  @spec optional(map(), String.t()) :: String.t() | nil
  def optional(args, key) do
    case string(args, key) do
      "" -> nil
      value -> value
    end
  end

  @doc "A reference argument, trimmed, with a single-chapter citation expanded."
  @spec reference(map(), String.t()) :: String.t()
  def reference(args, key \\ "reference") do
    case Map.get(args, key) do
      value when is_binary(value) -> value |> Reference.expand_single_chapter() |> String.trim()
      _ -> ""
    end
  end

  @doc "A boolean argument: `default` when absent; null is false."
  @spec flag(map(), String.t(), boolean()) :: boolean()
  def flag(args, key, default) do
    case Map.fetch(args, key) do
      {:ok, value} when is_boolean(value) -> value
      {:ok, nil} -> false
      _ -> default
    end
  end

  @doc """
  An integer argument (an integer, a whole float or a numeric string):
  `{:ok, n}`, `{:ok, default}` when absent or null, `:error` otherwise,
  including a number outside SQLite's 64-bit range (it can't be bound).
  """
  @spec integer(map(), String.t(), integer() | nil) :: {:ok, integer() | nil} | :error
  def integer(args, key, default) do
    case Map.get(args, key) do
      nil -> {:ok, default}
      n when is_integer(n) -> in_range(n)
      n when is_float(n) and n == trunc(n) -> in_range(trunc(n))
      n when is_binary(n) -> with {:ok, n} <- parse(n), do: in_range(n)
      _ -> :error
    end
  end

  @int64_min -0x8000000000000000
  @int64_max 0x7FFFFFFFFFFFFFFF

  defp in_range(n) when n >= @int64_min and n <= @int64_max, do: {:ok, n}
  defp in_range(_n), do: :error

  @doc "Is `n` an integer SQLite can bind (64-bit)?"
  defguard is_sqlite_integer(n) when is_integer(n) and n >= @int64_min and n <= @int64_max

  defp parse(text) do
    case Integer.parse(String.trim(text)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  @doc """
  A result limit: a positive integer argument, else `default` (a missing,
  zero, negative or unreadable limit returns the default number of rows).
  """
  @spec limit(map(), pos_integer()) :: pos_integer()
  def limit(args, default) do
    case integer(args, "limit", default) do
      {:ok, n} when n > 0 -> n
      _ -> default
    end
  end
end
