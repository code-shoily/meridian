defmodule Meridian.Render.MapLibre do
  @moduledoc """
  Renders a `Meridian.Graph` as an interactive MapLibre map in Livebook.

  Requires the optional dependencies `:maplibre`, `:kino_maplibre`, and `:jason`.

  ## Usage

      graph
      |> Meridian.Render.MapLibre.new()

  With options:

      graph
      |> Meridian.Render.MapLibre.new(
        style: :street,
        zoom: 12,
        node_color: "#e74c3c",
        edge_color: "#3498db"
      )

  The returned value is a `Kino.MapLibre` struct that renders directly in Livebook.
  """

  alias Meridian.Graph
  alias Meridian.Render.GeoJSON

  @default_node_color "#3FB1CE"
  @default_node_radius 6
  @default_edge_color "#888888"
  @default_edge_width 2
  @default_zoom 10

  @doc """
  Creates a MapLibre map from a `Meridian.Graph`.

  ## Options

    * `:center` — `{lng, lat}` tuple for initial map center. Defaults to the graph's
      bounding-box centroid or `{0.0, 0.0}` if the graph has no geometries.
    * `:zoom` — initial zoom level (default: `10`)
    * `:style` — MapLibre base style: `:default`, `:street`, `:terrain`, or a style URL
      (default: `:default`)
    * `:key` — MapTiler API key. Required when `:style` is `:street` or `:terrain`.
    * `:node_color` — circle color for point features (default: `"#3FB1CE"`)
    * `:node_radius` — circle radius in pixels (default: `6`)
    * `:edge_color` — line color for line features (default: `"#888888"`)
    * `:edge_width` — line width in pixels (default: `2`)
    * `:include_edges` — whether to render edges as line layers (default: `true`)

  """
  @spec new(Graph.t(), keyword()) :: Kino.MapLibre.t()
  def new(%Graph{} = graph, opts \\ []) do
    unless Code.ensure_loaded?(MapLibre) and Code.ensure_loaded?(Kino.MapLibre) and
             Code.ensure_loaded?(Jason) do
      raise ArgumentError,
            "Meridian.Render.MapLibre requires :maplibre, :kino_maplibre, and :jason to be available"
    end

    geojson = graph_to_geojson(graph, opts)
    center = opts[:center] || graph_center(graph)
    zoom = Keyword.get(opts, :zoom, @default_zoom)
    style = Keyword.get(opts, :style, :default)
    key = validate_key!(style, opts[:key])

    ml_opts = [center: center, zoom: zoom, style: style]
    ml_opts = if key, do: [{:key, key} | ml_opts], else: ml_opts

    ml =
      MapLibre.new(ml_opts)
      |> MapLibre.add_source("graph", type: :geojson, data: geojson)
      |> add_node_layer(opts)

    ml =
      if Keyword.get(opts, :include_edges, true) do
        add_edge_layer(ml, opts)
      else
        ml
      end

    Kino.MapLibre.new(ml)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp graph_to_geojson(%Graph{} = graph, opts) do
    include_edges = Keyword.get(opts, :include_edges, true)

    graph
    |> GeoJSON.to_string(include_edges: include_edges)
    |> Jason.decode!()
  end

  defp graph_center(%Graph{} = graph) do
    case Graph.nodes(graph) |> Enum.to_list() |> node_centroid() do
      {lng, lat} -> {lng, lat}
      nil -> {0.0, 0.0}
    end
  end

  defp node_centroid([]), do: nil

  defp node_centroid(nodes) do
    {sum_lng, sum_lat, count} =
      Enum.reduce(nodes, {0.0, 0.0, 0}, fn
        {_id, %{geometry: %Geo.Point{coordinates: {lng, lat}}}}, {sl, sa, c} ->
          {sl + lng, sa + lat, c + 1}

        _, acc ->
          acc
      end)

    if count > 0 do
      {sum_lng / count, sum_lat / count}
    else
      nil
    end
  end

  defp add_node_layer(ml, opts) do
    color = Keyword.get(opts, :node_color, @default_node_color)
    radius = Keyword.get(opts, :node_radius, @default_node_radius)

    MapLibre.add_layer(ml,
      id: "graph-nodes",
      type: :circle,
      source: "graph",
      filter: ["==", ["geometry-type"], "Point"],
      paint: [
        circle_color: color,
        circle_radius: radius,
        circle_stroke_color: "#ffffff",
        circle_stroke_width: 1
      ]
    )
  end

  defp add_edge_layer(ml, opts) do
    color = Keyword.get(opts, :edge_color, @default_edge_color)
    width = Keyword.get(opts, :edge_width, @default_edge_width)

    MapLibre.add_layer(ml,
      id: "graph-edges",
      type: :line,
      source: "graph",
      filter: ["==", ["geometry-type"], "LineString"],
      paint: [
        line_color: color,
        line_width: width
      ]
    )
  end

  defp validate_key!(:street, nil) do
    raise ArgumentError,
          "style: :street requires a MapTiler API key. Pass :key option or use style: :default"
  end

  defp validate_key!(:terrain, nil) do
    raise ArgumentError,
          "style: :terrain requires a MapTiler API key. Pass :key option or use style: :default"
  end

  defp validate_key!(_style, key), do: key
end
