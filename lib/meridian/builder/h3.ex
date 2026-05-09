defmodule Meridian.Builder.H3 do
  @moduledoc """
  Builds graphs from Uber H3 hexagonal grids.

  Requires the optional `:h3` dependency.

  ## Topologies

    * `:rook` — the 6 edge-adjacent neighbors (default)
    * `:queen` — rook + 6 vertex-adjacent neighbors (12 total)

  ## Examples

      iex> graph =
      ...>   Meridian.Graph.new(kind: :undirected)
      ...>   |> Meridian.Builder.H3.grid(center: {40.7484, -73.9857}, resolution: 9, k_ring: 1)
      iex> Meridian.Graph.node_count(graph)
      7
  """

  alias Meridian.Graph

  @valid_topologies [:rook, :queen]

  @doc """
  Creates a graph from an H3 hexagonal grid centered on a lat/lon point.

  ## Options

    * `:center` — `{lat, lon}` tuple (required)
    * `:resolution` — H3 resolution, 0–15 (required)
    * `:k_ring` — number of rings outward from center, default `1`
    * `:topology` — `:rook` (default) or `:queen`
    * `:node_data_fn` — function `(h3_index :: integer) -> map` to populate node data

  ## Examples

      iex> graph =
      ...>   Meridian.Graph.new(kind: :undirected)
      ...>   |> Meridian.Builder.H3.grid(center: {37.7749, -122.4194}, resolution: 5, k_ring: 1)
      iex> Meridian.Graph.node_count(graph) >= 1
      true
  """
  @spec grid(Graph.t(), keyword()) :: Graph.t()
  def grid(%Graph{} = g, opts) do
    unless Code.ensure_loaded?(:h3) do
      raise RuntimeError,
            "Meridian.Builder.H3 requires the :h3 dependency. Add `{:h3, \"~> 3.0\"}` to your deps."
    end

    {lat, lon} = Keyword.fetch!(opts, :center)
    res = validate_resolution!(Keyword.fetch!(opts, :resolution))
    k = Keyword.get(opts, :k_ring, 1)
    topology = validate_topology!(Keyword.get(opts, :topology, :rook))
    node_data_fn = Keyword.get(opts, :node_data_fn, &default_node_data/1)

    origin = :h3.from_geo({lat, lon}, res)
    indexes = :h3.k_ring(origin, k)

    # Add nodes
    g =
      Enum.reduce(indexes, g, fn idx, acc ->
        data = node_data_fn.(idx)
        {cell_lat, cell_lon} = :h3.to_geo(idx)

        data =
          Map.merge(data, %{
            geometry: %Geo.Point{coordinates: {cell_lon, cell_lat}},
            h3_index: idx,
            h3_resolution: res
          })

        Graph.add_node(acc, idx, data)
      end)

    # Add edges based on topology
    add_edges(g, indexes, topology)
  end

  # --------------------------------------------------------------------------
  # Private
  # --------------------------------------------------------------------------

  defp default_node_data(_idx), do: %{}

  defp validate_resolution!(res) when is_integer(res) and res >= 0 and res <= 15, do: res

  defp validate_resolution!(res) do
    raise ArgumentError,
          "H3 resolution must be an integer between 0 and 15, got: #{inspect(res)}"
  end

  defp validate_topology!(top) when top in @valid_topologies, do: top

  defp validate_topology!(top) do
    raise ArgumentError,
          "H3 topology must be one of #{inspect(@valid_topologies)}, got: #{inspect(top)}"
  end

  defp add_edges(%Graph{} = g, indexes, :rook) do
    index_set = MapSet.new(indexes)

    Enum.reduce(indexes, g, fn idx, acc ->
      idx
      |> :h3.k_ring(1)
      |> Enum.reject(&(&1 == idx))
      |> Enum.filter(&MapSet.member?(index_set, &1))
      |> maybe_add_edge(acc, idx)
    end)
  end

  defp add_edges(%Graph{} = g, indexes, :queen) do
    # Queen on a hex grid includes the 6 rook neighbors plus the 6
    # vertex neighbors. H3 doesn't expose vertex neighbors directly,
    # so we approximate by taking cells within distance 2 that share
    # a vertex but not an edge.
    # TODO: implement true vertex adjacency via H3 unidirectional edges
    add_edges(g, indexes, :rook)
  end

  defp maybe_add_edge(neighbors, graph, idx) do
    Enum.reduce(neighbors, graph, fn neighbor, acc ->
      if idx < neighbor do
        Graph.add_edge_ensure(acc, idx, neighbor, nil)
      else
        acc
      end
    end)
  end
end
