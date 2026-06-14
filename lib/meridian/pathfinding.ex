defmodule Meridian.Pathfinding do
  @moduledoc """
  Spatially-aware pathfinding wrappers around `yog_ex` algorithms.

  Injects geographic heuristics and distance-based edge weight functions
  into the core graph pathfinders. Supports dynamic node and edge filtering
  via `node_filter` and `weight_fn` options.

  ## Filtering

  Exclude closed roads by returning `:infinity` from `weight_fn`:

      weight_fn = fn _g, _from, _to, data ->
        if data.status == :closed, do: :infinity, else: data.distance
      end

      Meridian.Pathfinding.a_star(graph, from: :a, to: :b, weight_fn: weight_fn)

  Exclude nodes entirely (e.g., a closed intersection):

      node_filter = fn _id, data -> not data.closed? end

      Meridian.Pathfinding.shortest_path(graph, from: :a, to: :b, node_filter: node_filter)
  """

  alias Meridian.Builder.GTFS
  alias Meridian.{CRS, Graph}
  alias Yog.Pathfinding.{AStar, Dijkstra}

  @typedoc "Weight function. Return `nil` or `:infinity` to skip an edge."
  @type weight_fn ::
          (Graph.t(), Yog.node_id(), Yog.node_id(), any() -> number() | nil | :infinity)

  @typedoc "Node filter. Return `false` to exclude a node and all its edges."
  @type node_filter :: (Yog.node_id(), any() -> boolean())

  # ============================================================================
  # A*
  # ============================================================================

  @doc """
  A* shortest path using haversine distance as the heuristic.

  ## Options

    * `:from` — start node id (required)
    * `:to` — goal node id (required)
    * `:weight_fn` — function `(graph, from, to, data) -> number | nil | :infinity`.
      Defaults to `Meridian.CRS.distance/3` if nodes have point geometries.
      Return `nil` or `:infinity` to exclude the edge from consideration.
    * `:node_filter` — function `(node_id, data) -> boolean`. Return `false` to
      exclude the node and all incident edges.

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, 100.0)
      iex> {:ok, path} = Meridian.Pathfinding.a_star(g, from: :a, to: :b)
      iex> path.nodes
      [:a, :b]

  Skip a closed road:

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{})
      ...>   |> Meridian.Graph.add_node(:b, %{})
      ...>   |> Meridian.Graph.add_node(:c, %{})
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, %{distance: 1, status: :open})
      ...>   |> Meridian.Graph.add_edge_ensure(:b, :c, %{distance: 1, status: :closed})
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :c, %{distance: 5, status: :open})
      iex> weight_fn = fn _g, _f, _t, data ->
      ...>   if data.status == :closed, do: :infinity, else: data.distance
      ...> end
      iex> {:ok, path} = Meridian.Pathfinding.a_star(g, from: :a, to: :c, weight_fn: weight_fn)
      iex> path.nodes
      [:a, :c]
  """
  @spec a_star(Graph.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def a_star(%Graph{} = graph, opts) do
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)
    weight_fn = normalize_weight_fn(Keyword.get(opts, :weight_fn, &default_weight/4))
    node_filter = Keyword.get(opts, :node_filter, fn _, _ -> true end)

    validate_nodes!(graph, from, to)

    if Code.ensure_loaded?(Zog) and not Keyword.has_key?(opts, :weight_fn) and
         not Keyword.has_key?(opts, :node_filter) do
      run_zog_astar(graph, from, to)
    else
      simple = build_simple_graph(graph, weight_fn, node_filter)

      AStar.a_star(
        simple,
        from,
        to,
        haversine_heuristic(graph, to),
        0.0,
        &Kernel.+/2,
        &Kernel.<=/2
      )
    end
  end

  # ============================================================================
  # Dijkstra
  # ============================================================================

  @doc """
  Shortest path using Dijkstra's algorithm.

  Accepts the same `:weight_fn` and `:node_filter` options as `a_star/2`.

  ## Options

    * `:from` — start node id (required)
    * `:to` — goal node id (required)
    * `:weight_fn` — edge weight function (see `a_star/2`)
    * `:node_filter` — node predicate (see `a_star/2`)

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{})
      ...>   |> Meridian.Graph.add_node(:b, %{})
      ...>   |> Meridian.Graph.add_node(:c, %{})
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, 1)
      ...>   |> Meridian.Graph.add_edge_ensure(:b, :c, 1)
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :c, 5)
      iex> weight_fn = fn _g, _f, _t, data -> data end
      iex> {:ok, path} = Meridian.Pathfinding.shortest_path(g, from: :a, to: :c, weight_fn: weight_fn)
      iex> path.nodes
      [:a, :b, :c]
      iex> path.weight
      2
  """
  @spec shortest_path(Graph.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def shortest_path(%Graph{} = graph, opts) do
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)
    weight_fn = normalize_weight_fn(Keyword.get(opts, :weight_fn, &default_weight/4))
    node_filter = Keyword.get(opts, :node_filter, fn _, _ -> true end)

    validate_nodes!(graph, from, to)

    if Code.ensure_loaded?(Zog) and not Keyword.has_key?(opts, :weight_fn) and
         not Keyword.has_key?(opts, :node_filter) do
      run_zog_dijkstra(graph, from, to)
    else
      simple = build_simple_graph(graph, weight_fn, node_filter)

      Dijkstra.shortest_path(
        in: simple,
        from: from,
        to: to
      )
    end
  end

  # ============================================================================
  # Widest Path
  # ============================================================================

  @doc """
  Widest path (maximum bottleneck capacity) between two nodes.

  The widest path maximizes the minimum edge weight along the path.
  Useful for network routing where you want the path with the highest
  minimum capacity.

  ## Options

    * `:from` — start node id (required)
    * `:to` — goal node id (required)
    * `:node_filter` — node predicate (see `a_star/2`)

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{})
      ...>   |> Meridian.Graph.add_node(:b, %{})
      ...>   |> Meridian.Graph.add_node(:c, %{})
      ...>   |> Meridian.Graph.add_node(:d, %{})
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, 100)
      ...>   |> Meridian.Graph.add_edge_ensure(:b, :d, 80)
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :c, 50)
      ...>   |> Meridian.Graph.add_edge_ensure(:c, :d, 200)
      iex> weight_fn = fn _g, _f, _t, data -> data end
      iex> {:ok, path} = Meridian.Pathfinding.widest_path(g, from: :a, to: :d, weight_fn: weight_fn)
      iex> path.nodes
      [:a, :b, :d]
      iex> path.weight
      80
  """
  @spec widest_path(Graph.t(), keyword()) :: {:ok, map()} | :error
  def widest_path(%Graph{} = graph, opts) do
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)
    weight_fn = normalize_weight_fn(Keyword.get(opts, :weight_fn, &default_weight/4))
    node_filter = Keyword.get(opts, :node_filter, fn _, _ -> true end)

    validate_nodes!(graph, from, to)
    simple = build_simple_graph(graph, weight_fn, node_filter)

    Yog.Pathfinding.widest_path(simple, from, to)
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp validate_nodes!(graph, from, to) do
    unless Graph.has_node?(graph, from) do
      raise ArgumentError, "start node #{inspect(from)} does not exist in graph"
    end

    unless Graph.has_node?(graph, to) do
      raise ArgumentError, "goal node #{inspect(to)} does not exist in graph"
    end
  end

  defp normalize_weight_fn(fun) do
    case Function.info(fun, :arity) do
      {:arity, 3} ->
        fn graph, from, to, _data -> fun.(graph, from, to) end

      {:arity, 4} ->
        fun

      _ ->
        fun
    end
  end

  defp default_weight(graph, from, to, _data) do
    case CRS.distance(graph, from, to) do
      nil -> 1.0
      d -> d
    end
  end

  defp build_simple_graph(graph, weight_fn, node_filter) do
    # Filter nodes
    filtered_nodes =
      Enum.filter(graph.graph.nodes, fn {id, data} -> node_filter.(id, data) end)
      |> Map.new()

    # Build simple graph with filtered nodes
    base = %Yog.Graph{
      kind: graph.graph.kind,
      nodes: filtered_nodes,
      out_edges: %{},
      in_edges: %{}
    }

    # Add edges, skipping those with nil/:infinity weights or missing endpoints
    Enum.reduce(Yog.all_edges(graph.graph), base, fn edge, g ->
      maybe_add_edge(g, edge, graph, weight_fn, filtered_nodes)
    end)
  end

  defp maybe_add_edge(g, {from, to, data}, graph, weight_fn, filtered_nodes) do
    if Map.has_key?(filtered_nodes, from) and Map.has_key?(filtered_nodes, to) do
      w = weight_fn.(graph, from, to, data)
      if is_number(w), do: Yog.Model.add_edge!(g, from, to, w), else: g
    else
      g
    end
  end

  defp run_zog_astar(graph, from, to) do
    graph_with_weights = CRS.compute_edge_weights(graph)
    builder = Zog.from_graph(graph_with_weights.graph)

    {x_coords, y_coords} =
      Enum.reduce(graph.graph.nodes, {%{}, %{}}, fn {id, data}, {xs, ys} ->
        case data do
          %{geometry: %Geo.Point{coordinates: {lon, lat}}} ->
            {Map.put(xs, id, lon), Map.put(ys, id, lat)}

          _ ->
            {xs, ys}
        end
      end)

    case Zog.Pathfinding.astar(builder, from, to, x_coords, y_coords, :euclidean) do
      {:ok, {path, weight}} ->
        {:ok,
         %Yog.Pathfinding.Path{nodes: path, weight: weight, algorithm: :a_star, metadata: %{}}}

      {:error, :no_path} ->
        {:error, :no_path}
    end
  end

  defp run_zog_dijkstra(graph, from, to) do
    graph_with_weights = CRS.compute_edge_weights(graph)
    builder = Zog.from_graph(graph_with_weights.graph)

    case Zog.Pathfinding.dijkstra(builder, from, to) do
      {:ok, {path, weight}} ->
        {:ok,
         %Yog.Pathfinding.Path{nodes: path, weight: weight, algorithm: :dijkstra, metadata: %{}}}

      {:error, :no_path} ->
        {:error, :no_path}
    end
  end

  defp haversine_heuristic(graph, to) do
    fn current, _goal ->
      case CRS.distance(graph, current, to) do
        nil -> 0.0
        d -> d
      end
    end
  end

  # ============================================================================
  # GTFS earliest_arrival/2 (Connection-Scan Algorithm)
  # ============================================================================

  @doc """
  Runs the Connection-Scan Algorithm (CSA) to find the earliest arrival journey
  between two stops in a GTFS timetable graph.

  ## Options

    * `:from` — origin stop ID (required)
    * `:to` — destination stop ID (required)
    * `:departure_time` — Time struct of departure (required)
    * `:date` — Date struct to filter active calendar schedules (optional)
    * `:max_transfers` — maximum allowed transfers (optional)
    * `:walk_speed_mps` — walk speed in meters per second (default: `1.4`)
    * `:max_walk_transfer_m` — maximum walk distance in meters (optional)

  ## Examples

      # {:ok, journey} = Meridian.Pathfinding.earliest_arrival(graph,
      #   from: "union",
      #   to: "kipling",
      #   departure_time: ~T[08:00:00],
      #   date: ~D[2026-05-12]
      # )
  """
  @spec earliest_arrival(Graph.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def earliest_arrival(%Graph{} = graph, opts) do
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)
    departure_time = Keyword.fetch!(opts, :departure_time)
    date = Keyword.get(opts, :date)
    max_transfers = Keyword.get(opts, :max_transfers)
    walk_speed_mps = Keyword.get(opts, :walk_speed_mps, 1.4)
    max_walk_transfer_m = Keyword.get(opts, :max_walk_transfer_m)

    validate_nodes!(graph, from, to)

    dep_secs = GTFS.time_to_seconds(departure_time)

    active_services =
      if date && graph.calendar do
        GTFS.active_service_ids_for_date(graph.calendar, date)
      else
        nil
      end

    connections = get_connections(graph, dep_secs, active_services)
    walk_map = build_walk_map(graph, max_walk_transfer_m)

    initial_state = {%{from => dep_secs}, %{from => -1}, %{}}

    {s_arr, transfers_at_stop, connection_to} =
      apply_initial_walks(walk_map, from, dep_secs, walk_speed_mps, initial_state)

    transfers_of_trip = %{}

    {s_arr, connection_to, _t_stop, _t_trip} =
      Enum.reduce(
        connections,
        {s_arr, connection_to, transfers_at_stop, transfers_of_trip},
        fn conn, {s, c_to, t_stop, t_trip} ->
          scan_connection(
            conn,
            {s, c_to, t_stop, t_trip},
            {max_transfers, walk_map, walk_speed_mps, from}
          )
        end
      )

    reconstruct_journey_result(s_arr, connection_to, from, to)
  end

  defp get_connections(graph, dep_secs, active_services) do
    graph
    |> Graph.edges()
    |> Stream.flat_map(&extract_connections/1)
    |> Stream.filter(fn conn ->
      conn.departure_time >= dep_secs and
        (is_nil(active_services) or MapSet.member?(active_services, conn.service_id))
    end)
    |> Enum.sort_by(& &1.departure_time)
  end

  defp extract_connections({u, v, conn_list}) when is_list(conn_list) do
    Enum.map(conn_list, fn conn -> Map.merge(conn, %{from: u, to: v}) end)
  end

  defp extract_connections(_), do: []

  defp build_walk_map(_graph, max_walk) when is_nil(max_walk) or max_walk <= 0, do: %{}

  defp build_walk_map(graph, max_walk) do
    stops_list = Map.keys(Graph.nodes(graph))

    Enum.into(stops_list, %{}, fn stop_id ->
      {stop_id, find_nearby_stops(graph, stop_id, stops_list, max_walk)}
    end)
  end

  defp find_nearby_stops(graph, stop_id, stops_list, max_walk) do
    stops_list
    |> Stream.reject(&(&1 == stop_id))
    |> Stream.map(fn other_id -> {other_id, stop_distance(graph, stop_id, other_id)} end)
    |> Stream.filter(fn {_other_id, dist} -> dist <= max_walk end)
    |> Enum.to_list()
  end

  defp apply_initial_walks(walk_map, from, dep_secs, walk_speed_mps, initial_state) do
    case Map.get(walk_map, from) do
      nil ->
        initial_state

      near_stops ->
        Enum.reduce(near_stops, initial_state, fn {to_id, dist}, {s, t, c_to} ->
          walk_time = round(dist / walk_speed_mps)
          arr_time = dep_secs + walk_time

          {
            Map.put(s, to_id, arr_time),
            Map.put(t, to_id, -1),
            Map.put(c_to, to_id, %{
              type: :walk,
              from: from,
              to: to_id,
              duration: walk_time,
              arrival_time: arr_time
            })
          }
        end)
    end
  end

  defp scan_connection(conn, {s, _c_to, _t_stop, t_trip} = state, config) do
    can_board_from_stop = Map.get(s, conn.from, :infinity) <= conn.departure_time
    can_board_from_trip = Map.get(t_trip, conn.trip_id, :infinity) <= conn.departure_time

    if can_board_from_stop or can_board_from_trip do
      process_boarded_connection(conn, state, can_board_from_trip, config)
    else
      state
    end
  end

  defp process_boarded_connection(conn, state, can_board_from_trip, config) do
    {s, c_to, t_stop, t_trip} = state
    {max_transfers, walk_map, walk_speed_mps, from} = config

    {trip_transfers, t_trip_new} =
      get_trip_transfers(conn, t_trip, t_stop, can_board_from_trip, from)

    if is_nil(max_transfers) or trip_transfers <= max_transfers do
      update_arrival_and_walk(
        conn,
        {s, c_to, t_stop, t_trip_new},
        trip_transfers,
        walk_map,
        walk_speed_mps
      )
    else
      {s, c_to, t_stop, t_trip}
    end
  end

  defp get_trip_transfers(conn, t_trip, _t_stop, true = _can_board_from_trip, _from) do
    {Map.fetch!(t_trip, conn.trip_id), t_trip}
  end

  defp get_trip_transfers(conn, t_trip, t_stop, false = _can_board_from_trip, from) do
    curr_stop_transfers = Map.fetch!(t_stop, conn.from)

    transfers =
      if conn.from == from do
        0
      else
        curr_stop_transfers + 1
      end

    {transfers, Map.put(t_trip, conn.trip_id, transfers)}
  end

  defp update_arrival_and_walk(
         conn,
         {s, c_to, t_stop, t_trip_new},
         trip_transfers,
         walk_map,
         walk_speed_mps
       ) do
    current_best = Map.get(s, conn.to, :infinity)

    if conn.arrival_time < current_best do
      s_new = Map.put(s, conn.to, conn.arrival_time)
      t_stop_new = Map.put(t_stop, conn.to, trip_transfers)
      c_to_new = Map.put(c_to, conn.to, conn)

      propagate_walks(
        Map.get(walk_map, conn.to),
        conn,
        {s_new, c_to_new, t_stop_new, t_trip_new},
        trip_transfers,
        walk_speed_mps
      )
    else
      {s, c_to, t_stop, t_trip_new}
    end
  end

  defp propagate_walks(nil, _conn, state, _trip_transfers, _walk_speed_mps), do: state

  defp propagate_walks(
         near_stops,
         conn,
         {s_acc, c_acc, t_acc, tt_acc},
         trip_transfers,
         walk_speed_mps
       ) do
    Enum.reduce(
      near_stops,
      {s_acc, c_acc, t_acc, tt_acc},
      fn {near_id, dist}, {s, c, t, tt} ->
        walk_time = round(dist / walk_speed_mps)
        walk_arr_time = conn.arrival_time + walk_time

        if walk_arr_time < Map.get(s, near_id, :infinity) do
          {
            Map.put(s, near_id, walk_arr_time),
            Map.put(c, near_id, %{
              type: :walk,
              from: conn.to,
              to: near_id,
              duration: walk_time,
              arrival_time: walk_arr_time
            }),
            Map.put(t, near_id, trip_transfers),
            tt
          }
        else
          {s, c, t, tt}
        end
      end
    )
  end

  defp stop_distance(graph, id1, id2) do
    case {Graph.node(graph, id1), Graph.node(graph, id2)} do
      {%{geometry: p1}, %{geometry: p2}} ->
        Geocalc.distance_between(
          [elem(p1.coordinates, 1), elem(p1.coordinates, 0)],
          [elem(p2.coordinates, 1), elem(p2.coordinates, 0)]
        )

      _ ->
        :infinity
    end
  end

  defp reconstruct_journey(connection_to, from, to) do
    reconstruct_journey(connection_to, from, to, [])
  end

  defp reconstruct_journey(_connection_to, from, from, acc), do: {:ok, acc}

  defp reconstruct_journey(connection_to, from, current, acc) do
    case Map.get(connection_to, current) do
      nil ->
        :error

      %{type: :walk} = walk ->
        leg = %{
          from: walk.from,
          to: walk.to,
          trip: "walk",
          trip_id: "walk",
          route_id: "walk",
          dep: GTFS.seconds_to_time(walk.arrival_time - walk.duration),
          arr: GTFS.seconds_to_time(walk.arrival_time),
          departure_time: GTFS.seconds_to_time(walk.arrival_time - walk.duration),
          arrival_time: GTFS.seconds_to_time(walk.arrival_time)
        }

        reconstruct_journey(connection_to, from, walk.from, [leg | acc])

      conn ->
        leg = %{
          from: conn.from,
          to: conn.to,
          trip: conn.trip_id,
          trip_id: conn.trip_id,
          route_id: conn.route_id,
          dep: GTFS.seconds_to_time(conn.departure_time),
          arr: GTFS.seconds_to_time(conn.arrival_time),
          departure_time: GTFS.seconds_to_time(conn.departure_time),
          arrival_time: GTFS.seconds_to_time(conn.arrival_time)
        }

        reconstruct_journey(connection_to, from, conn.from, [leg | acc])
    end
  end

  defp compress_legs(legs) do
    Enum.reduce(legs, [], fn
      leg, [] ->
        [leg]

      leg, [prev | rest] ->
        if leg.trip_id != "walk" and leg.trip_id == prev.trip_id do
          merged = %{
            prev
            | from: leg.from,
              dep: leg.dep,
              departure_time: leg.departure_time
          }

          [merged | rest]
        else
          [leg, prev | rest]
        end
    end)
    |> Enum.reverse()
  end

  defp reconstruct_journey_result(s_arr, connection_to, from, to) do
    if Map.has_key?(s_arr, to) do
      case reconstruct_journey(connection_to, from, to) do
        {:ok, legs} ->
          compressed = compress_legs(legs)
          arr_secs = Map.fetch!(s_arr, to)

          {:ok,
           %{
             arrival_time: GTFS.seconds_to_time(arr_secs),
             legs: compressed
           }}

        :error ->
          {:error, :no_path}
      end
    else
      {:error, :no_path}
    end
  end
end
