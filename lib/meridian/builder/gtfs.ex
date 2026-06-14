defmodule Meridian.Builder.GTFS do
  @moduledoc """
  Builds spatial graphs from General Transit Feed Specification (GTFS) data.

  Requires the optional `:req` dependency for remote zip files.
  """

  alias Meridian.Graph

  @day_names {"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"}

  @doc """
  Builds a spatial graph from a GTFS ZIP file path or binary.

  ## Options

    * `:route_types` — list of allowed route types (e.g. `[0, 1]` for subway/light rail)
    * `:service_date` — Date struct to filter active trips/schedules

  ## Examples

      # {:ok, graph} = Meridian.Builder.GTFS.from_zip("gtfs.zip")
  """
  @spec from_zip(Path.t() | binary(), keyword()) :: {:ok, Graph.t()} | {:error, term()}
  def from_zip(zip_path_or_binary, opts \\ []) do
    unzip_res =
      if is_binary(zip_path_or_binary) and not File.exists?(zip_path_or_binary) do
        :zip.unzip(zip_path_or_binary, [:memory])
      else
        :zip.unzip(to_charlist(zip_path_or_binary), [:memory])
      end

    case unzip_res do
      {:ok, files} ->
        files_map =
          Enum.into(files, %{}, fn {name_charlist, binary} ->
            name = to_string(name_charlist)
            basename = Path.basename(name)
            {basename, trim_bom(binary)}
          end)

        build_graph(files_map, opts)

      {:error, reason} ->
        {:error, "failed to unzip GTFS archive: #{inspect(reason)}"}
    end
  end

  @doc """
  Builds a spatial graph from a directory of extracted GTFS text files.
  """
  @spec from_dir(Path.t(), keyword()) :: {:ok, Graph.t()} | {:error, term()}
  def from_dir(dir_path, opts \\ []) do
    if File.dir?(dir_path) do
      read_required_files(dir_path, opts)
    else
      {:error, "directory does not exist: #{dir_path}"}
    end
  end

  defp read_required_files(dir_path, opts) do
    required_files = ["stops.txt", "routes.txt", "trips.txt", "stop_times.txt", "calendar.txt"]

    files_map_or_error =
      Enum.reduce_while(required_files, {:ok, %{}}, fn filename, {:ok, acc} ->
        read_file_to_map(dir_path, filename, acc)
      end)

    case files_map_or_error do
      {:ok, files_map} ->
        build_graph(files_map, opts)

      {:error, {filename, reason}} ->
        {:error, "failed to read #{filename}: #{inspect(reason)}"}
    end
  end

  defp read_file_to_map(dir_path, filename, acc) do
    path = Path.join(dir_path, filename)

    case File.read(path) do
      {:ok, binary} ->
        {:cont, {:ok, Map.put(acc, filename, trim_bom(binary))}}

      {:error, reason} ->
        {:halt, {:error, {filename, reason}}}
    end
  end

  @doc """
  Returns all departures from a given stop after the specified time.
  """
  @spec departures_from(Graph.t(), String.t(), keyword()) :: [map()]
  def departures_from(%Graph{} = graph, stop_id, opts \\ []) do
    after_time = Keyword.get(opts, :after, ~T[00:00:00])
    after_secs = time_to_seconds(after_time)

    case Map.get(graph.graph.out_edges, stop_id) do
      nil ->
        []

      edges_map ->
        edges_map
        |> Enum.flat_map(fn {_to_stop, conn_list} -> conn_list end)
        |> Enum.filter(fn conn -> conn.departure_time >= after_secs end)
        |> Enum.sort_by(fn conn -> conn.departure_time end)
        |> Enum.map(fn conn ->
          %{
            trip_id: conn.trip_id,
            route_id: conn.route_id,
            departure_time: seconds_to_time(conn.departure_time),
            arrival_time: seconds_to_time(conn.arrival_time),
            to: conn.to
          }
        end)
    end
  end

  @doc """
  Returns all active service IDs for a given date based on the graph's calendar.
  """
  @spec service_ids_for(Graph.t(), Date.t()) :: [String.t()]
  def service_ids_for(%Graph{} = graph, %Date{} = date) do
    if graph.calendar do
      active_service_ids_for_date(graph.calendar, date) |> MapSet.to_list()
    else
      []
    end
  end

  @doc """
  Returns the active service IDs from a calendar list for a given date.
  """
  @spec active_service_ids_for_date(list(map()), Date.t()) :: MapSet.t(String.t())
  def active_service_ids_for_date(calendar, %Date{} = date) do
    day_name = elem(@day_names, Date.day_of_week(date) - 1)
    date_int = date_to_yyyymmdd(date)

    calendar
    |> Stream.filter(fn row ->
      start_date = String.to_integer(Map.fetch!(row, "start_date"))
      end_date = String.to_integer(Map.fetch!(row, "end_date"))
      runs_on_day = Map.fetch!(row, day_name) == "1"

      date_int >= start_date and date_int <= end_date and runs_on_day
    end)
    |> Stream.map(fn row -> Map.fetch!(row, "service_id") end)
    |> MapSet.new()
  end

  # Helpers for time conversion
  @doc false
  def time_to_seconds(%Time{hour: h, minute: m, second: s}) do
    h * 3600 + m * 60 + s
  end

  @doc false
  def seconds_to_time(seconds) do
    Time.add(~T[00:00:00], rem(seconds, 86_400))
  end

  @doc false
  def parse_time_to_seconds(time_str) do
    time_str = String.trim(time_str)

    case String.split(time_str, ":") do
      [h, m, s] ->
        sec =
          case Float.parse(s) do
            {f, _} -> round(f)
            :error -> 0
          end

        String.to_integer(h) * 3600 + String.to_integer(m) * 60 + sec

      _ ->
        0
    end
  end

  # Private functions

  defp trim_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp trim_bom(binary), do: binary

  defp parse_csv(binary) do
    case NimbleCSV.RFC4180.parse_string(binary, skip_headers: false) do
      [headers | rows] ->
        Enum.map(rows, fn row ->
          Enum.zip(headers, row) |> Map.new()
        end)

      [] ->
        []
    end
  end

  defp build_graph(files_map, opts) do
    stops = parse_csv(Map.fetch!(files_map, "stops.txt"))
    routes = parse_csv(Map.fetch!(files_map, "routes.txt"))
    calendar = parse_csv(Map.fetch!(files_map, "calendar.txt"))
    trips = parse_csv(Map.fetch!(files_map, "trips.txt"))
    stop_times = parse_csv(Map.fetch!(files_map, "stop_times.txt"))

    allowed_route_types = Keyword.get(opts, :route_types)

    routes_map =
      routes
      |> Stream.filter(fn r ->
        is_nil(allowed_route_types) or
          String.to_integer(Map.fetch!(r, "route_type")) in allowed_route_types
      end)
      |> Stream.map(fn r -> {Map.fetch!(r, "route_id"), r} end)
      |> Map.new()

    service_date = Keyword.get(opts, :service_date)

    active_service_ids =
      if service_date do
        active_service_ids_for_date(calendar, service_date)
      else
        calendar |> Enum.map(&Map.fetch!(&1, "service_id")) |> MapSet.new()
      end

    trips_map =
      trips
      |> Stream.filter(fn t ->
        Map.has_key?(routes_map, Map.fetch!(t, "route_id")) and
          MapSet.member?(active_service_ids, Map.fetch!(t, "service_id"))
      end)
      |> Stream.map(fn t -> {Map.fetch!(t, "trip_id"), t} end)
      |> Map.new()

    stop_times_by_trip =
      stop_times
      |> Stream.filter(fn st -> Map.has_key?(trips_map, Map.fetch!(st, "trip_id")) end)
      |> Enum.group_by(fn st -> Map.fetch!(st, "trip_id") end)

    graph = %{Graph.new(kind: :directed) | calendar: calendar}

    # Add stops
    graph =
      Enum.reduce(stops, graph, fn s, graph_acc ->
        stop_id = Map.fetch!(s, "stop_id")
        lat = String.to_float(Map.fetch!(s, "stop_lat"))
        lon = String.to_float(Map.fetch!(s, "stop_lon"))
        name = Map.fetch!(s, "stop_name")

        tags = Map.drop(s, ["stop_id", "stop_lat", "stop_lon", "stop_name"])

        node_data = %{
          geometry: %Geo.Point{coordinates: {lon, lat}},
          name: name,
          gtfs_stop_id: stop_id,
          tags: tags
        }

        Graph.add_node(graph_acc, stop_id, node_data)
      end)

    # Add connections
    connections =
      Enum.flat_map(stop_times_by_trip, fn {trip_id, st_list} ->
        sorted_st =
          Enum.sort_by(st_list, fn st ->
            String.to_integer(Map.fetch!(st, "stop_sequence"))
          end)

        trip = Map.fetch!(trips_map, trip_id)
        route_id = Map.fetch!(trip, "route_id")
        service_id = Map.fetch!(trip, "service_id")
        headsign = Map.get(trip, "trip_headsign", "")

        sorted_st
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [st1, st2] ->
          build_connection(st1, st2, trip_id, route_id, service_id, headsign)
        end)
      end)

    connections_by_stops = Enum.group_by(connections, fn c -> {c.from, c.to} end)

    graph =
      Enum.reduce(connections_by_stops, graph, fn {{from, to}, conn_list}, graph_acc ->
        sorted_conn = Enum.sort_by(conn_list, & &1.departure_time)

        if Graph.has_node?(graph_acc, from) and Graph.has_node?(graph_acc, to) do
          Graph.add_edge_ensure(graph_acc, from, to, sorted_conn)
        else
          graph_acc
        end
      end)

    {:ok, Graph.recompute_bounds(graph)}
  end

  defp date_to_yyyymmdd(%Date{year: y, month: m, day: d}) do
    y * 10_000 + m * 100 + d
  end

  defp build_connection(st1, st2, trip_id, route_id, service_id, headsign) do
    dep_time_str = Map.fetch!(st1, "departure_time")
    arr_time_str = Map.fetch!(st2, "arrival_time")
    from_stop = Map.fetch!(st1, "stop_id")
    to_stop = Map.fetch!(st2, "stop_id")
    stop_sequence = String.to_integer(Map.fetch!(st1, "stop_sequence"))

    shape_dist_traveled =
      case Map.get(st1, "shape_dist_traveled") do
        nil -> nil
        "" -> nil
        val -> String.to_float(val)
      end

    %{
      from: from_stop,
      to: to_stop,
      trip_id: trip_id,
      route_id: route_id,
      service_id: service_id,
      departure_time: parse_time_to_seconds(dep_time_str),
      arrival_time: parse_time_to_seconds(arr_time_str),
      stop_sequence: stop_sequence,
      headsign: headsign,
      shape_dist_traveled: shape_dist_traveled
    }
  end
end
