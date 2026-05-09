defmodule Meridian.Analysis do
  @moduledoc """
  Spatial graph analysis and metrics.

  Computes network-wide measures that require both graph topology and
  geographic embedding, such as geographic diameter, average path length,
  and spatial density.

  ## Examples

  Geographic diameter of a Toronto street network:

      Meridian.Analysis.diameter(graph)
      # => %{distance_m: 12_450.0, from: :union_station, to: :high_park, path: [...]}
  """

  alias Meridian.{Graph, Pathfinding}
  alias Yog.Pathfinding.Dijkstra

  @typedoc "Result from `diameter/2`."
  @type diameter_result :: %{
          distance_m: float(),
          from: Yog.node_id(),
          to: Yog.node_id(),
          path: [Yog.node_id()]
        }

  # ============================================================================
  # Diameter
  # ============================================================================

  @doc """
  Computes the **geographic diameter** of a graph — the longest shortest-path
  between any two nodes, measured in meters.

  Runs Dijkstra from every node in parallel to find the exact diameter pair,
  then returns the shortest path between that pair. Returns `nil` if the graph
  is empty or disconnected.

  ## Options

    * `:weight_fn` — edge weight function `(graph, from, to, data) -> number`.
      Defaults to `Meridian.CRS.distance/3` for geographic graphs, or `1.0`
      for graphs without geometries. Return `nil` or `:infinity` to skip edges.

  ## Examples

  A small Toronto network: Union Station → Yonge-Dundas → High Park:

      iex> g = Meridian.Graph.new(kind: :undirected)
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:union, %{geometry: %Geo.Point{coordinates: {-79.380, 43.645}}})
      ...>   |> Meridian.Graph.add_node(:yonge_dundas, %{geometry: %Geo.Point{coordinates: {-79.380, 43.656}}})
      ...>   |> Meridian.Graph.add_node(:high_park, %{geometry: %Geo.Point{coordinates: {-79.465, 43.647}}})
      ...>   |> Meridian.Graph.add_node(:distillery, %{geometry: %Geo.Point{coordinates: {-79.360, 43.650}}})
      iex> g = g
      ...>   |> Meridian.Graph.add_edge_ensure(:union, :yonge_dundas, nil)
      ...>   |> Meridian.Graph.add_edge_ensure(:yonge_dundas, :high_park, nil)
      ...>   |> Meridian.Graph.add_edge_ensure(:union, :distillery, nil)
      iex> result = Meridian.Analysis.diameter(g)
      iex> result.from
      :distillery
      iex> result.to
      :high_park
      iex> result.distance_m > 8_000 and result.distance_m < 10_000
      true
      iex> result.path
      [:distillery, :union, :yonge_dundas, :high_park]

  With a custom weight function:

      iex> g = Meridian.Graph.new(kind: :undirected)
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {-79.380, 43.645}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {-79.380, 43.656}}})
      ...>   |> Meridian.Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {-79.465, 43.647}}})
      iex> g = g
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, nil)
      ...>   |> Meridian.Graph.add_edge_ensure(:b, :c, nil)
      iex> weight_fn = fn graph, from, to, _data ->
      ...>   case Meridian.CRS.distance(graph, from, to) do
      ...>     nil -> 1.0
      ...>     d -> d
      ...>   end
      ...> end
      iex> result = Meridian.Analysis.diameter(g, weight_fn: weight_fn)
      iex> result.distance_m > 8_000 and result.distance_m < 10_000
      true

  Empty graph returns `nil`:

      iex> Meridian.Analysis.diameter(Meridian.Graph.new())
      nil

  Disconnected graph returns `nil`:

      iex> g = Meridian.Graph.new(kind: :undirected)
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {1.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {2.0, 0.0}}})
      iex> g = g
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, nil)
      iex> Meridian.Analysis.diameter(g)
      nil
  """
  @spec diameter(Graph.t(), keyword()) :: diameter_result() | nil
  def diameter(%Graph{} = graph, opts \\ []) do
    weight_fn = Keyword.get(opts, :weight_fn, &default_weight/4)
    simple = build_simple_graph(graph, weight_fn)
    nodes = Map.keys(simple.nodes)

    case nodes do
      [] ->
        nil

      _ ->
        num_nodes = length(nodes)
        results = all_eccentricities(nodes, simple, num_nodes)

        case diameter_pair(results) do
          nil ->
            nil

          {from, to} ->
            {:ok, path_result} =
              Pathfinding.shortest_path(graph,
                from: from,
                to: to,
                weight_fn: weight_fn
              )

            %{
              distance_m: path_result.weight,
              from: from,
              to: to,
              path: path_result.nodes
            }
        end
    end
  end

  @doc """
  Computes the **average edge length** of a graph in meters.

  Only considers edges where both endpoints have `%Geo.Point{}` geometries.
  Returns `0.0` for empty graphs or graphs without geometries.

  ## Examples

      iex> g = Meridian.Graph.new(kind: :undirected)
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {-79.380, 43.645}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {-79.380, 43.656}}})
      ...>   |> Meridian.Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {-79.465, 43.647}}})
      iex> g = g
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, nil)
      ...>   |> Meridian.Graph.add_edge_ensure(:b, :c, nil)
      iex> avg = Meridian.Analysis.average_edge_length(g)
      iex> avg > 3_500 and avg < 4_500
      true
  """
  @spec average_edge_length(Graph.t()) :: float()
  def average_edge_length(%Graph{} = graph) do
    edges =
      Graph.edges(graph)
      |> Enum.filter(fn {from, to, _data} ->
        has_point?(graph, from) and has_point?(graph, to)
      end)

    case edges do
      [] -> 0.0
      _ -> sum_edge_distances(edges, graph) / length(edges)
    end
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp all_eccentricities(nodes, simple, num_nodes) do
    nodes
    |> Task.async_stream(
      fn node -> eccentricity(simple, node, num_nodes) end,
      max_concurrency: System.schedulers_online(),
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, r} -> r end)
    |> Enum.reject(&is_nil/1)
  end

  defp eccentricity(simple, node, num_nodes) do
    distances = Dijkstra.single_source_distances(simple, node)

    if map_size(distances) < num_nodes do
      nil
    else
      {farthest, max_dist} = Enum.max_by(distances, fn {_, d} -> d end)
      {node, farthest, max_dist}
    end
  end

  defp diameter_pair([]), do: nil

  defp diameter_pair(results) do
    {from, to, _dist} =
      results
      |> Enum.map(fn {a, b, d} -> if a <= b, do: {a, b, d}, else: {b, a, d} end)
      |> Enum.max_by(fn {a, b, d} -> {d, a, b} end)

    {from, to}
  end

  defp build_simple_graph(graph, weight_fn) do
    base = %Yog.Graph{
      kind: graph.graph.kind,
      nodes: graph.graph.nodes,
      out_edges: %{},
      in_edges: %{}
    }

    Enum.reduce(Yog.all_edges(graph.graph), base, fn {from, to, data}, g ->
      w = weight_fn.(graph, from, to, data)

      if is_number(w) do
        Yog.Model.add_edge!(g, from, to, w)
      else
        g
      end
    end)
  end

  defp default_weight(graph, from, to, _data) do
    case Meridian.CRS.distance(graph, from, to) do
      nil -> 1.0
      d -> d
    end
  end

  defp has_point?(graph, node_id) do
    case Graph.node(graph, node_id) do
      %{geometry: %Geo.Point{}} -> true
      _ -> false
    end
  end

  defp sum_edge_distances(edges, graph) do
    Enum.reduce(edges, 0.0, fn {from, to, _data}, acc ->
      case Meridian.CRS.distance(graph, from, to) do
        nil -> acc
        d -> acc + d
      end
    end)
  end
end
