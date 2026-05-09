defmodule Meridian.Render.MapLibreTest do
  use ExUnit.Case

  alias Meridian.Graph

  @moduletag :maplibre

  describe "new/2" do
    test "renders a graph with nodes" do
      graph =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      kino = Meridian.Render.MapLibre.new(graph)
      assert %Kino.JS.Live{module: Kino.MapLibre} = kino
    end

    test "accepts styling options" do
      graph =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {-74.0, 40.7}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {-74.0, 40.8}}})
        |> Graph.add_edge_ensure(:a, :b, nil)

      kino =
        Meridian.Render.MapLibre.new(graph,
          style: :default,
          zoom: 12,
          node_color: "#e74c3c",
          edge_color: "#3498db",
          include_edges: true
        )

      assert %Kino.JS.Live{module: Kino.MapLibre} = kino
    end

    test "omits edges when include_edges: false" do
      graph =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      kino = Meridian.Render.MapLibre.new(graph, include_edges: false)
      assert %Kino.JS.Live{module: Kino.MapLibre} = kino
    end

    test "uses default center for empty graph" do
      graph = Graph.new()
      kino = Meridian.Render.MapLibre.new(graph)
      assert %Kino.JS.Live{module: Kino.MapLibre} = kino
    end

    test "raises when :street is used without a key" do
      graph =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      assert_raise ArgumentError, ~r/style: :street requires a MapTiler API key/, fn ->
        Meridian.Render.MapLibre.new(graph, style: :street)
      end
    end

    test "raises when :terrain is used without a key" do
      graph =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      assert_raise ArgumentError, ~r/style: :terrain requires a MapTiler API key/, fn ->
        Meridian.Render.MapLibre.new(graph, style: :terrain)
      end
    end
  end
end
