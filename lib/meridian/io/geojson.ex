defmodule Meridian.IO.GeoJSON do
  @moduledoc """
  Ingests GeoJSON into `Meridian.Graph` structures.

  Requires the optional `:jason` dependency.

  ## Supported Geometry Types

    * `Point` — single node
    * `LineString` — edge path; intermediate vertices become nodes
    * `MultiLineString` — multiple edges
    * `Polygon` — ring of edges
    * `FeatureCollection` — iterated over features

  ## Examples

      geojson = ~s[{"type":"FeatureCollection","features":[...]}]
      {:ok, graph} = Meridian.IO.GeoJSON.from_string(geojson)
  """

  alias Meridian.Graph

  @doc """
  Parses a GeoJSON string and builds a `Meridian.Graph`.

  Returns `{:ok, graph}` on success or `{:error, reason}` on failure.

  ## Options

    * `:kind` — `:directed` (default) or `:undirected`
    * `:crs` — CRS string override, default `"EPSG:4326"`
    * `:weight_fn` — function `(%Geo.LineString{} -> number)` to compute edge weights

  ## Examples

      iex> geojson = ~s|{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"LineString","coordinates":[[0,0],[0,1]]},"properties":{}}]}|
      iex> {:ok, graph} = Meridian.IO.GeoJSON.from_string(geojson)
      iex> Meridian.Graph.node_count(graph) == 2
      true
      iex> Meridian.Graph.edge_count(graph) == 1
      true
  """
  @spec from_string(String.t(), keyword()) :: {:ok, Graph.t()} | {:error, String.t()}
  def from_string(json, opts \\ []) do
    unless Code.ensure_loaded?(Jason) do
      raise RuntimeError,
            "Meridian.IO.GeoJSON requires the :jason dependency. Add `{:jason, \"~> 1.4\"}` to your deps."
    end

    case Jason.decode(json) do
      {:ok, data} ->
        try do
          graph = from_map(data, opts)
          {:ok, graph}
        rescue
          e in ArgumentError -> {:error, e.message}
        end

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  @doc """
  Parses a GeoJSON string and builds a `Meridian.Graph`, raising on error.
  """
  @spec from_string!(String.t(), keyword()) :: Graph.t()
  def from_string!(json, opts \\ []) do
    case from_string(json, opts) do
      {:ok, graph} -> graph
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Reads a GeoJSON file and builds a `Meridian.Graph`.

  Returns `{:ok, graph}` on success or `{:error, reason}` on failure.
  """
  @spec from_file(Path.t(), keyword()) :: {:ok, Graph.t()} | {:error, String.t()}
  def from_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, contents} -> from_string(contents, opts)
      {:error, reason} -> {:error, "cannot read #{path}: #{inspect(reason)}"}
    end
  end

  @doc """
  Reads a GeoJSON file and builds a `Meridian.Graph`, raising on error.
  """
  @spec from_file!(Path.t(), keyword()) :: Graph.t()
  def from_file!(path, opts \\ []) do
    case from_file(path, opts) do
      {:ok, graph} -> graph
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Builds a graph from a decoded GeoJSON map.
  """
  @spec from_map(map(), keyword()) :: Graph.t()
  def from_map(geojson, opts \\ []) do
    kind = Keyword.get(opts, :kind, :directed)
    crs = Keyword.get(opts, :crs, "EPSG:4326")
    weight_fn = Keyword.get(opts, :weight_fn, &Meridian.Geometry.geo_length/1)

    graph = Graph.new(kind: kind, crs: crs)

    case geojson do
      %{"type" => "FeatureCollection", "features" => features} ->
        Enum.reduce(features, graph, fn feature, acc ->
          ingest_feature(acc, feature, weight_fn)
        end)

      %{"type" => "Feature"} = feature ->
        ingest_feature(graph, feature, weight_fn)

      %{"type" => geom_type}
      when geom_type in ["Point", "LineString", "Polygon", "MultiLineString"] ->
        ingest_geometry(graph, geojson, %{}, weight_fn)

      %{} ->
        raise ArgumentError, "unsupported GeoJSON type: #{inspect(Map.get(geojson, "type"))}"

      _ ->
        raise ArgumentError, "GeoJSON must be a map, got: #{inspect(geojson)}"
    end
    |> Graph.recompute_bounds()
  end

  # --------------------------------------------------------------------------
  # Private
  # --------------------------------------------------------------------------

  defp ingest_feature(graph, %{"geometry" => geom, "properties" => props}, weight_fn) do
    ingest_geometry(graph, geom, props, weight_fn)
  end

  defp ingest_feature(graph, %{"geometry" => geom}, weight_fn) do
    ingest_geometry(graph, geom, %{}, weight_fn)
  end

  defp ingest_geometry(
         graph,
         %{"type" => "Point", "coordinates" => [lon, lat]},
         props,
         _weight_fn
       ) do
    id = System.unique_integer([:positive])
    point = %Geo.Point{coordinates: {lon, lat}}
    Graph.add_node(graph, id, Map.merge(props, %{geometry: point}))
  end

  defp ingest_geometry(
         graph,
         %{"type" => "LineString", "coordinates" => coords},
         _props,
         weight_fn
       ) do
    line = %Geo.LineString{coordinates: Enum.map(coords, fn [lon, lat] -> {lon, lat} end)}

    {graph, node_ids} =
      Enum.reduce(line.coordinates, {graph, []}, fn {lon, lat}, {g, ids} ->
        id = System.unique_integer([:positive])
        g = Graph.add_node(g, id, %{geometry: %Geo.Point{coordinates: {lon, lat}}})
        {g, [id | ids]}
      end)

    node_ids = Enum.reverse(node_ids)
    weight = weight_fn.(line)

    {graph, _} =
      Enum.reduce(Enum.chunk_every(node_ids, 2, 1, :discard), {graph, nil}, fn [a, b], {g, _} ->
        {Graph.add_edge_ensure(g, a, b, weight), nil}
      end)

    graph
  end

  defp ingest_geometry(
         graph,
         %{"type" => "MultiLineString", "coordinates" => lines},
         props,
         weight_fn
       ) do
    Enum.reduce(lines, graph, fn coords, g ->
      ingest_geometry(g, %{"type" => "LineString", "coordinates" => coords}, props, weight_fn)
    end)
  end

  defp ingest_geometry(
         graph,
         %{"type" => "Polygon", "coordinates" => [ring | _]},
         props,
         weight_fn
       ) do
    # Treat exterior ring as a closed LineString
    ingest_geometry(graph, %{"type" => "LineString", "coordinates" => ring}, props, weight_fn)
  end

  defp ingest_geometry(graph, %{"type" => _type}, _props, _weight_fn) do
    # Silently skip unsupported geometry types (MultiPolygon, GeometryCollection, etc.)
    graph
  end
end
