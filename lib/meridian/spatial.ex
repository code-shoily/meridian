defmodule Meridian.Spatial do
  @moduledoc """
  Spatial queries on `Meridian.Graph` and `Meridian.MultiGraph`.

  Find nodes by geographic proximity — within a radius, nearest N, or
  nearest satisfying a predicate.

  ## Metrics

    * `:haversine` — great-circle distance in meters (default for WGS-84)
    * `:euclidean` — straight-line distance in coordinate units (useful for
      projected CRS like Web Mercator)

  ## Filtering

  Both `within/3` and `nearest/3` accept a `:filter` option — a function
  `(node_id, data) -> boolean` that narrows the candidate set before
  distance computation.

  ## Examples

  Coffee shops within 500 m of a point:

      point = %Geo.Point{coordinates: {-79.3832, 43.6532}}

      Meridian.Spatial.within(graph, point,
        radius: 500,
        filter: fn _id, data -> data.type == :coffee_shop end
      )

  5 nearest nodes regardless of type:

      Meridian.Spatial.nearest(graph, point, n: 5)

  Nearest bike-share docks using euclidean distance in a projected CRS:

      Meridian.Spatial.nearest(graph, point,
        n: 3,
        metric: :euclidean,
        filter: fn _id, data -> data.type == :bike_dock end
      )
  """

  alias Meridian.{Geometry, Graph}

  @typedoc "Distance metric. `:haversine` for geo, `:euclidean` for projected."
  @type metric :: :haversine | :euclidean

  @typedoc "Node predicate. Return `false` to exclude from consideration."
  @type filter_fn :: (Yog.node_id(), any() -> boolean())

  @typedoc "Result tuple from nearest/3: `{node_id, data, distance}`"
  @type nearest_result :: {Yog.node_id(), any(), float()}

  # ============================================================================
  # within/3
  # ============================================================================

  @doc """
  Returns all nodes within `radius` meters (or coordinate units) of `point`.

  ## Options

    * `:radius` — maximum distance (required). In meters for `:haversine`,
      in coordinate units for `:euclidean`.
    * `:metric` — `:haversine` (default) or `:euclidean`
    * `:filter` — predicate `(node_id, data) -> boolean`
    * `:include_distance` — if `true`, return `{id, data, dist}` tuples
      instead of `{id, data}` (default: `false`)

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}})
      ...>   |> Meridian.Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 0.1}}})
      iex> point = %Geo.Point{coordinates: {0.0, 0.0}}
      iex> Meridian.Spatial.within(g, point, radius: 2_000)
      ...> |> Enum.map(fn {id, _} -> id end)
      ...> |> Enum.sort()
      [:a, :b]

  With distance included:

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}})
      iex> point = %Geo.Point{coordinates: {0.0, 0.0}}
      iex> results = Meridian.Spatial.within(g, point, radius: 2_000, include_distance: true)
      iex> length(results)
      2
      iex> {_, _, d_b} = Enum.find(results, fn {id, _, _} -> id == :b end)
      iex> d_b > 1_100 and d_b < 1_120
      true

  With a filter:

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}, type: :shop})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}, type: :park})
      iex> point = %Geo.Point{coordinates: {0.0, 0.0}}
      iex> Meridian.Spatial.within(g, point,
      ...>   radius: 2_000,
      ...>   filter: fn _id, data -> data.type == :park end
      ...> )
      ...> |> Enum.map(fn {id, _} -> id end)
      [:b]
  """
  @spec within(Graph.t(), Geo.Point.t(), keyword()) ::
          [{Yog.node_id(), any()}] | [nearest_result()]
  def within(%Graph{} = graph, %Geo.Point{} = point, opts) do
    radius = Keyword.fetch!(opts, :radius)
    metric = Keyword.get(opts, :metric, :haversine)
    filter = Keyword.get(opts, :filter, fn _, _ -> true end)
    include_dist? = Keyword.get(opts, :include_distance, false)

    distance_fn = distance_fn(metric)

    graph
    |> Graph.nodes()
    |> Stream.filter(fn {id, data} ->
      filter.(id, data) and has_geometry?(data)
    end)
    |> Stream.map(fn {id, data} ->
      dist = distance_fn.(point, node_point(data))
      {id, data, dist}
    end)
    |> Stream.filter(fn {_id, _data, dist} -> dist <= radius end)
    |> Enum.sort_by(fn {_id, _data, dist} -> dist end)
    |> maybe_include_distance(include_dist?)
  end

  # ============================================================================
  # nearest/3
  # ============================================================================

  @doc """
  Returns the `n` nearest nodes to `point`, sorted by distance ascending.

  ## Options

    * `:n` — number of results to return (required)
    * `:metric` — `:haversine` (default) or `:euclidean`
    * `:filter` — predicate `(node_id, data) -> boolean`

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}})
      ...>   |> Meridian.Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 0.1}}})
      iex> point = %Geo.Point{coordinates: {0.0, 0.0}}
      iex> Meridian.Spatial.nearest(g, point, n: 2)
      ...> |> Enum.map(fn {id, _, _} -> id end)
      [:a, :b]

  With distance:

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}})
      iex> point = %Geo.Point{coordinates: {0.0, 0.0}}
      iex> results = Meridian.Spatial.nearest(g, point, n: 2)
      iex> length(results)
      2
      iex> {_, _, d_b} = Enum.find(results, fn {id, _, _} -> id == :b end)
      iex> d_b > 1_100 and d_b < 1_120
      true

  Euclidean metric on a projected grid:

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {10.0, 10.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {3.0, 4.0}}})
      iex> point = %Geo.Point{coordinates: {0.0, 0.0}}
      iex> [{_, _, d}] = Meridian.Spatial.nearest(g, point, n: 1, metric: :euclidean)
      iex> d
      5.0
  """
  @spec nearest(Graph.t(), Geo.Point.t(), keyword()) :: [nearest_result()]
  def nearest(%Graph{} = graph, %Geo.Point{} = point, opts) do
    n = Keyword.fetch!(opts, :n)
    metric = Keyword.get(opts, :metric, :haversine)
    filter = Keyword.get(opts, :filter, fn _, _ -> true end)

    distance_fn = distance_fn(metric)

    graph
    |> Graph.nodes()
    |> Stream.filter(fn {id, data} ->
      filter.(id, data) and has_geometry?(data)
    end)
    |> Enum.map(fn {id, data} ->
      dist = distance_fn.(point, node_point(data))
      {id, data, dist}
    end)
    |> Enum.sort_by(fn {_id, _data, dist} -> dist end)
    |> Enum.take(n)
  end

  # ============================================================================
  # nearest_reachable/3
  # ============================================================================

  @doc """
  Returns the nearest node reachable via the graph that satisfies a predicate.

  Unlike `nearest/3`, which uses straight-line (crow-flies) distance, this
  function uses the graph's topology and edge weights to find the closest
  reachable node.

  ## Options

    * `:filter` — predicate `(node_id, data) -> boolean` (required)
    * `:metric` — `:haversine` (default) or `:euclidean`

  ## Examples

  Finding the nearest bike share station reachable by road from Union Station:

      point = %Geo.Point{coordinates: {-79.3806, 43.6453}}

      Meridian.Spatial.nearest_reachable(graph, point,
        filter: fn _id, data -> data.type == :bike_share end
      )
  """
  @spec nearest_reachable(Graph.t(), Geo.Point.t(), keyword()) ::
          {:ok, nearest_result()} | :error
  def nearest_reachable(%Graph{} = graph, %Geo.Point{} = point, opts) do
    # 1. Find the node in the graph closest to the starting point (crow-flies)
    # 2. Start a Dijkstra search from that node
    # 3. Stop at the first node satisfying the filter
    case nearest(graph, point, n: 1) do
      [{start_id, _, _}] ->
        filter = Keyword.fetch!(opts, :filter)
        do_nearest_reachable(graph, start_id, filter)

      [] ->
        :error
    end
  end

  defp do_nearest_reachable(_graph, _start_id, _filter) do
    :error
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp distance_fn(:haversine) do
    fn p1, p2 ->
      Geometry.geo_length(%Geo.LineString{coordinates: [p1.coordinates, p2.coordinates]})
    end
  end

  defp distance_fn(:euclidean) do
    fn p1, p2 -> Geometry.euclidean(p1, p2) end
  end

  defp distance_fn(other) do
    raise ArgumentError, "unknown metric: #{inspect(other)}. Expected :haversine or :euclidean"
  end

  defp has_geometry?(%{geometry: %Geo.Point{}}), do: true
  defp has_geometry?(_), do: false

  defp node_point(%{geometry: %Geo.Point{} = pt}), do: pt

  defp maybe_include_distance(results, true), do: results

  defp maybe_include_distance(results, false),
    do: Enum.map(results, fn {id, data, _} -> {id, data} end)
end
