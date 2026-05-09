defmodule Meridian.Pathfinding do
  @moduledoc """
  Spatially-aware pathfinding wrappers around `yog_ex` algorithms.

  Injects geographic heuristics and distance-based edge weight functions
  into the core graph pathfinders.
  """

  alias Meridian.{CRS, Graph}

  @doc """
  A* shortest path using haversine distance as the heuristic.

  ## Options

    * `:from` — start node id (required)
    * `:to` — goal node id (required)
    * `:weight_fn` — function `(graph, from, to) -> number` for edge cost.
      Defaults to `Meridian.CRS.distance/3` if nodes have point geometries.

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, 100.0)
      iex> {:ok, path} = Meridian.Pathfinding.a_star(g, from: :a, to: :b)
      iex> path.nodes
      [:a, :b]

      iex> g = Meridian.Graph.new()
      iex> Meridian.Pathfinding.a_star(g, from: :missing, to: :also_missing)
      ** (ArgumentError) start node :missing does not exist in graph
  """
  @spec a_star(Graph.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def a_star(%Graph{} = graph, opts) do
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)
    weight_fn = Keyword.get(opts, :weight_fn, &default_weight/3)

    unless Graph.has_node?(graph, from) do
      raise ArgumentError, "start node #{inspect(from)} does not exist in graph"
    end

    unless Graph.has_node?(graph, to) do
      raise ArgumentError, "goal node #{inspect(to)} does not exist in graph"
    end

    # Build a simple graph with computed weights
    simple =
      Enum.reduce(Yog.all_edges(graph.graph), graph.graph, fn {u, v, _old}, g ->
        w = weight_fn.(graph, u, v)
        Yog.add_edge_ensure(g, u, v, w)
      end)

    heuristic = fn current, _goal ->
      case CRS.distance(graph, current, to) do
        nil -> 0.0
        d -> d
      end
    end

    Yog.Pathfinding.AStar.a_star(
      simple,
      from,
      to,
      heuristic,
      0.0,
      &Kernel.+/2,
      &Kernel.<=/2
    )
  end

  # --------------------------------------------------------------------------
  # Private
  # --------------------------------------------------------------------------

  defp default_weight(graph, from, to) do
    case Meridian.CRS.distance(graph, from, to) do
      nil -> 1.0
      d -> d
    end
  end
end
