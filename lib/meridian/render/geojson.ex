defmodule Meridian.Render.GeoJSON do
  @moduledoc """
  Renders a `Meridian.Graph` as GeoJSON.

  Requires the optional `:jason` dependency for JSON output.

  ## Examples

      graph =
        Meridian.Graph.new()
        |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}, name: "A"})
        |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {1.0, 1.0}}, name: "B"})
        |> Meridian.Graph.add_edge_ensure(:a, :b, %{distance: 10.0})

      geojson = Meridian.Render.GeoJSON.to_string(graph)
  """

  alias Meridian.Graph

  @doc """
  Converts a spatial graph to a GeoJSON FeatureCollection string.

  ## Options

    * `:include_edges` — emit edges as `LineString` features (default `true`)
    * `:edge_properties_fn` — function `(from, to, weight) -> map` for edge props
    * `:node_properties_fn` — function `(id, data) -> map` for node props

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}, label: "A"})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {1.0, 1.0}}, label: "B"})
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, %{distance: 10.0})
      iex> json = Meridian.Render.GeoJSON.to_string(g)
      iex> String.contains?(json, "FeatureCollection")
      true
  """
  @spec to_string(Graph.t(), keyword()) :: String.t()
  def to_string(%Graph{} = graph, opts \\ []) do
    unless Code.ensure_loaded?(Jason) do
      raise RuntimeError,
            "Meridian.Render.GeoJSON requires the :jason dependency. Add `{:jason, \"~> 1.4\"}` to your deps."
    end

    include_edges = Keyword.get(opts, :include_edges, true)
    edge_props = Keyword.get(opts, :edge_properties_fn, fn _, _, _ -> %{} end)

    node_props =
      Keyword.get(opts, :node_properties_fn, fn _, data -> Map.drop(data, [:geometry]) end)

    node_features =
      Enum.map(graph.graph.nodes, fn {id, data} ->
        geom = data[:geometry]

        feature(%{
          "type" => "Feature",
          "geometry" => geo_to_json(geom),
          "properties" => Map.merge(node_props.(id, data), %{"_node_id" => id})
        })
      end)

    edge_features =
      if include_edges do
        graph.graph
        |> Yog.all_edges()
        |> Enum.map(fn {from, to, weight} ->
          geom = edge_geometry(graph, from, to)

          feature(%{
            "type" => "Feature",
            "geometry" => geo_to_json(geom),
            "properties" =>
              Map.merge(edge_props.(from, to, weight), %{
                "_from" => from,
                "_to" => to,
                "_weight" => weight
              })
          })
        end)
      else
        []
      end

    Jason.encode!(%{
      "type" => "FeatureCollection",
      "features" => node_features ++ edge_features
    })
  end

  @doc """
  Writes a spatial graph to a GeoJSON file.

  ## Options

  Accepts the same options as `to_string/2`.
  """
  @spec to_file(Graph.t(), Path.t(), keyword()) :: :ok | {:error, File.posix()}
  def to_file(%Graph{} = graph, path, opts \\ []) do
    File.write(path, to_string(graph, opts))
  end

  # --------------------------------------------------------------------------
  # Private
  # --------------------------------------------------------------------------

  defp feature(map), do: map

  defp geo_to_json(nil), do: nil

  defp geo_to_json(%Geo.Point{coordinates: {lon, lat}}) do
    %{
      "type" => "Point",
      "coordinates" => [lon, lat]
    }
  end

  defp geo_to_json(%Geo.LineString{coordinates: coords}) do
    %{
      "type" => "LineString",
      "coordinates" => Enum.map(coords, fn {lon, lat} -> [lon, lat] end)
    }
  end

  defp geo_to_json(%Geo.Polygon{coordinates: rings}) do
    %{
      "type" => "Polygon",
      "coordinates" =>
        Enum.map(rings, fn ring -> Enum.map(ring, fn {lon, lat} -> [lon, lat] end) end)
    }
  end

  defp edge_geometry(%Graph{} = graph, from, to) do
    from_geom = get_in(graph.graph.nodes, [from, :geometry])
    to_geom = get_in(graph.graph.nodes, [to, :geometry])

    case {from_geom, to_geom} do
      {%Geo.Point{coordinates: c1}, %Geo.Point{coordinates: c2}} ->
        %Geo.LineString{coordinates: [c1, c2]}

      _ ->
        %Geo.LineString{coordinates: []}
    end
  end
end
