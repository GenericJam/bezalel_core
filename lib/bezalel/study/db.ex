defmodule Bezalel.Study.DB do
  @moduledoc """
  Read-only access to the study packs (built by the phone app's
  `data/build.sh`, GenericJam/bezalel_mob; `data/README.md` there, and by
  this repository's `data/`): `core`, `notes`, `lxx`, `ancient`, `graph`,
  `translations` and `scrolls`, one SQLite file each in `dir/0`.

  Every call opens its own read-only connection to the one pack it needs
  and closes it when done (`with_pack/2`), so:

    * calls are independent: rho runs a reply's tool calls in parallel, and
      no connection or statement is shared between processes;
    * a pack downloaded or replaced while the app runs is used from the next
      call, with no connection to reopen or repo to restart;
    * a missing pack is found per call and reported as text the model can
      act on (`missing/1`).

  Opening a pack costs about a millisecond on a Mac, small beside a tool
  call's model round trip. Exqlite is used directly rather than through a
  second Ecto repo: the tools run fixed SQL over a fixed schema, and a
  pooled repo would hold connections open across pack downloads and need
  `ATTACH` on every pooled connection for the packs present at the time.
  """

  alias Exqlite.Sqlite3

  @packs %{
    core: "Bible text, lexicon, names and cross references",
    notes: "study notes and Bible dictionary",
    lxx: "Septuagint",
    ancient: "ancient sources",
    graph: "people, places and events",
    translations: "Bible translations",
    scrolls: "Dead Sea Scrolls",
    fathers: "Apostolic Fathers"
  }

  @type pack ::
          :core | :notes | :lxx | :ancient | :graph | :translations | :scrolls | :fathers
  @type conn :: Sqlite3.db()
  @type row :: %{String.t() => term()}

  @doc """
  The packs directory, for the study tools and the host app's pack
  downloads alike: `config :bezalel_core, :packs_dir`, either a path or
  `{module, function, args}` returning one, called on every use. Bezalel's
  phone app names its app-support directory (`Bezalel.Packs.Storage`), which
  is resolved at run time; tests set a path.
  """
  @spec dir() :: Path.t()
  def dir do
    case Application.fetch_env(:bezalel_core, :packs_dir) do
      {:ok, dir} when is_binary(dir) ->
        dir

      {:ok, {module, function, args}} ->
        apply(module, function, args)

      _unset ->
        raise ArgumentError,
              "config :bezalel_core, :packs_dir is not set: give the study packs' directory " <>
                "or {module, function, args} returning it"
    end
  end

  @doc "The file of `pack`."
  @spec path(pack()) :: Path.t()
  def path(pack) when is_map_key(@packs, pack), do: Path.join(dir(), "#{pack}.sqlite")

  @doc "Is `pack` on this device?"
  @spec available?(pack()) :: boolean()
  def available?(pack), do: File.regular?(path(pack))

  @doc "The message a tool returns when `pack` is not downloaded."
  @spec missing(pack()) :: String.t()
  def missing(pack) do
    "The #{pack} study pack (#{Map.fetch!(@packs, pack)}) isn't downloaded on this " <>
      "device, so this tool can't answer. Tell the user it needs the #{pack} pack; " <>
      "don't answer from memory as if the tool had."
  end

  @doc """
  Runs `fun` with a read-only connection to `pack` and returns
  `{:ok, result}`, or `{:error, message}` when the pack is missing or isn't
  a readable pack (a broken download). The connection is closed
  afterwards, also when `fun` raises.
  """
  @spec with_pack(pack(), (conn() -> result)) :: {:ok, result} | {:error, String.t()}
        when result: term()
  def with_pack(pack, fun) do
    file = path(pack)

    with true <- File.regular?(file) || {:error, missing(pack)},
         {:ok, conn} <- open(pack, file) do
      try do
        {:ok, fun.(conn)}
      after
        Sqlite3.close(conn)
      end
    end
  end

  # SQLite reads the file on the first statement, so a cheap one checks it
  # is a pack before a tool's queries run.
  defp open(pack, file) do
    with {:ok, conn} <- Sqlite3.open(file, mode: :readonly),
         :ok <- checked(conn, Sqlite3.execute(conn, "SELECT 1 FROM pack_meta LIMIT 1")) do
      {:ok, conn}
    else
      {:error, reason} ->
        {:error,
         "The #{pack} study pack on this device can't be read (#{reason}); " <>
           "it may need downloading again."}
    end
  end

  defp checked(_conn, :ok), do: :ok

  defp checked(conn, error) do
    Sqlite3.close(conn)
    error
  end

  @doc """
  `:ok` if every table in `tables` (virtual tables too) can be read on
  `conn`, else the error a tool returns for a damaged `pack` (`with_pack/2`
  checks only `pack_meta`).
  """
  @spec check_tables(conn(), pack(), [String.t()]) :: :ok | {:error, String.t()}
  def check_tables(conn, pack, tables) do
    case Enum.reject(tables, &readable?(conn, &1)) do
      [] ->
        :ok

      missing ->
        {:error,
         "The #{pack} study pack on this device can't be read (no #{Enum.join(missing, ", ")}); " <>
           "it may need downloading again."}
    end
  end

  defp readable?(conn, table) do
    case Sqlite3.prepare(conn, "SELECT 1 FROM #{table} LIMIT 0") do
      {:ok, statement} ->
        Sqlite3.release(conn, statement)
        true

      {:error, _reason} ->
        false
    end
  end

  @doc "Every row of `sql` with `params`, as maps keyed by column name."
  @spec all(conn(), String.t(), list()) :: [row()]
  def all(conn, sql, params \\ []) do
    {:ok, statement} = Sqlite3.prepare(conn, sql)

    try do
      :ok = Sqlite3.bind(statement, params)
      {:ok, columns} = Sqlite3.columns(conn, statement)
      {:ok, rows} = Sqlite3.fetch_all(conn, statement)
      Enum.map(rows, &(columns |> Enum.zip(&1) |> Map.new()))
    after
      Sqlite3.release(conn, statement)
    end
  end

  @doc "The first row of `sql` with `params`, or nil."
  @spec one(conn(), String.t(), list()) :: row() | nil
  def one(conn, sql, params \\ []), do: conn |> all(sql, params) |> List.first()

  @doc "`?, ?, …` for `values`, for an `IN (…)` list."
  @spec placeholders(list()) :: String.t()
  def placeholders(values), do: Enum.map_join(values, ", ", fn _ -> "?" end)
end
