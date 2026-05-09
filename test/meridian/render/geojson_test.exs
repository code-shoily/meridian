defmodule Meridian.Render.GeoJSONTest do
  use ExUnit.Case, async: true

  alias Meridian.{Graph, Render.GeoJSON}

  doctest Meridian.Render.GeoJSON

  describe "to_string/2" do
    test "renders nodes and edges" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}, label: "A"})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {1.0, 1.0}}, label: "B"})
        |> Graph.add_edge_ensure(:a, :b, %{distance: 10.0})

      json = GeoJSON.to_string(g)
      assert String.contains?(json, "FeatureCollection")
      assert String.contains?(json, "_node_id")
      assert String.contains?(json, "_from")
    end

    test "can omit edges" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      json = GeoJSON.to_string(g, include_edges: false)
      refute String.contains?(json, "_from")
    end
  end

  describe "to_file/3" do
    test "writes to temp file" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      path = Path.join(System.tmp_dir!(), "meridian_test_#{System.unique_integer()}.geojson")
      assert :ok = GeoJSON.to_file(g, path)
      assert File.exists?(path)
      File.rm!(path)
    end
  end
end
