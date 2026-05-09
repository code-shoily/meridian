defmodule Meridian.Builder.Geohash do
  @moduledoc """
  Builds graphs from geohash rectangular grids.

  Requires the optional `:geohash` dependency.

  Uses a flood-fill approach starting from the center of the bounding box
  to discover all geohash cells that intersect the area.

  ## Topologies

    * `:rook` — 4 cardinal neighbors (default)
    * `:queen` — 8 neighbors including diagonals

  ## Examples

      iex> graph =
      ...>   Meridian.Graph.new(kind: :undirected)
      ...>   |> Meridian.Builder.Geohash.grid(
      ...>        sw: {40.6, -74.1},
      ...>        ne: {40.8, -73.9},
      ...>        precision: 5,
      ...>        topology: :rook
      ...>      )
      iex> Meridian.Graph.node_count(graph) >= 1
      true
  """

  alias Meridian.Graph

  @valid_topologies [:rook, :queen]

  @doc """
  Creates a graph covering a bounding box with geohash cells.

  ## Options

    * `:sw` — southwest corner `{lat, lon}` (required)
    * `:ne` — northeast corner `{lat, lon}` (required)
    * `:precision` — geohash character length, 1–12 (required)
    * `:topology` — `:rook` (default) or `:queen`
    * `:node_data_fn` — function `(geohash :: String.t()) -> map`

  ## Examples

      iex> graph =
      ...>   Meridian.Graph.new(kind: :undirected)
      ...>   |> Meridian.Builder.Geohash.grid(sw: {0.0, 0.0}, ne: {0.1, 0.1}, precision: 5)
      iex> Meridian.Graph.node_count(graph) >= 1
      true
  """
  @spec grid(Graph.t(), keyword()) :: Graph.t()
  def grid(%Graph{} = g, opts) do
    unless Code.ensure_loaded?(Geohash) do
      raise RuntimeError,
            "Meridian.Builder.Geohash requires the :geohash dependency. Add `{:geohash, \"~> 1.3\"}` to your deps."
    end

    {min_lat, min_lon} = Keyword.fetch!(opts, :sw)
    {max_lat, max_lon} = Keyword.fetch!(opts, :ne)
    precision = validate_precision!(Keyword.fetch!(opts, :precision))
    topology = validate_topology!(Keyword.get(opts, :topology, :rook))
    node_data_fn = Keyword.get(opts, :node_data_fn, &default_node_data/1)

    center_lat = (min_lat + max_lat) / 2.0
    center_lon = (min_lon + max_lon) / 2.0
    start_hash = Geohash.encode(center_lat, center_lon, precision)

    hashes = flood_fill(start_hash, min_lat, min_lon, max_lat, max_lon, precision)

    # Add nodes
    g =
      Enum.reduce(hashes, g, fn hash, acc ->
        {lat, lon} = Geohash.decode(hash)

        data =
          node_data_fn.(hash)
          |> Map.merge(%{
            geometry: %Geo.Point{coordinates: {lon, lat}},
            geohash: hash,
            geohash_precision: precision
          })

        Graph.add_node(acc, hash, data)
      end)

    add_geohash_edges(g, hashes, topology)
  end

  defp add_geohash_edges(graph, hashes, topology) do
    hash_set = MapSet.new(hashes)

    Enum.reduce(hashes, graph, fn hash, acc ->
      hash
      |> geohash_neighbors(topology)
      |> Enum.filter(&MapSet.member?(hash_set, &1))
      |> add_neighbors_to_graph(acc, hash)
    end)
  end

  defp add_neighbors_to_graph(neighbors, graph, hash) do
    Enum.reduce(neighbors, graph, fn neighbor, acc ->
      if hash < neighbor do
        Graph.add_edge_ensure(acc, hash, neighbor, nil)
      else
        acc
      end
    end)
  end

  # --------------------------------------------------------------------------
  # Private
  # --------------------------------------------------------------------------

  defp default_node_data(_hash), do: %{}

  defp validate_precision!(p) when is_integer(p) and p >= 1 and p <= 12, do: p

  defp validate_precision!(p) do
    raise ArgumentError,
          "geohash precision must be an integer between 1 and 12, got: #{inspect(p)}"
  end

  defp validate_topology!(top) when top in @valid_topologies, do: top

  defp validate_topology!(top) do
    raise ArgumentError,
          "geohash topology must be one of #{inspect(@valid_topologies)}, got: #{inspect(top)}"
  end

  defp flood_fill(start_hash, min_lat, min_lon, max_lat, max_lon, precision) do
    do_flood_fill(
      [start_hash],
      MapSet.new(),
      min_lat,
      min_lon,
      max_lat,
      max_lon,
      precision
    )
  end

  defp do_flood_fill([], seen, _min_lat, _min_lon, _max_lat, _max_lon, _precision) do
    MapSet.to_list(seen)
  end

  defp do_flood_fill([hash | rest], seen, min_lat, min_lon, max_lat, max_lon, precision) do
    cond do
      MapSet.member?(seen, hash) ->
        do_flood_fill(rest, seen, min_lat, min_lon, max_lat, max_lon, precision)

      inside_bbox?(hash, min_lat, min_lon, max_lat, max_lon) ->
        seen = MapSet.put(seen, hash)
        next = cardinal_neighbors(hash, precision)
        do_flood_fill(next ++ rest, seen, min_lat, min_lon, max_lat, max_lon, precision)

      true ->
        do_flood_fill(rest, seen, min_lat, min_lon, max_lat, max_lon, precision)
    end
  end

  defp inside_bbox?(hash, min_lat, min_lon, max_lat, max_lon) do
    {lat, lon} = Geohash.decode(hash)
    lat >= min_lat and lat <= max_lat and lon >= min_lon and lon <= max_lon
  end

  defp cardinal_neighbors(hash, precision) do
    neighbors = Geohash.neighbors(hash)

    [neighbors["n"], neighbors["s"], neighbors["e"], neighbors["w"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn h -> String.length(h) == precision end)
  end

  defp geohash_neighbors(hash, :rook) do
    neighbors = Geohash.neighbors(hash)

    [neighbors["n"], neighbors["s"], neighbors["e"], neighbors["w"]]
    |> Enum.reject(&is_nil/1)
  end

  defp geohash_neighbors(hash, :queen) do
    neighbors = Geohash.neighbors(hash)

    [
      neighbors["n"],
      neighbors["s"],
      neighbors["e"],
      neighbors["w"],
      neighbors["ne"],
      neighbors["nw"],
      neighbors["se"],
      neighbors["sw"]
    ]
    |> Enum.reject(&is_nil/1)
  end
end
