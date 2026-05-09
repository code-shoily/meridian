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
    simple = build_simple_graph(graph, weight_fn, node_filter)

    heuristic = fn current, _goal ->
      case CRS.distance(graph, current, to) do
        nil -> 0.0
        d -> d
      end
    end

    AStar.a_star(
      simple,
      from,
      to,
      heuristic,
      0.0,
      &Kernel.+/2,
      &Kernel.<=/2
    )
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
    simple = build_simple_graph(graph, weight_fn, node_filter)

    Dijkstra.shortest_path(
      in: simple,
      from: from,
      to: to
    )
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
end
