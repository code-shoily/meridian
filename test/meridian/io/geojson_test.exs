defmodule Meridian.IO.GeoJSONTest do
  use ExUnit.Case, async: true

  alias Meridian.{Graph, IO.GeoJSON}

  doctest Meridian.IO.GeoJSON

  describe "from_string/2" do
    test "ingests FeatureCollection with LineString" do
      json = ~s"""
      {"type":"FeatureCollection","features":[
        {"type":"Feature","geometry":{"type":"LineString","coordinates":[[0,0],[0,1]]},"properties":{"name":"road"}}
      ]}
      """

      assert {:ok, graph} = GeoJSON.from_string(json)
      assert Graph.node_count(graph) == 2
      assert Graph.edge_count(graph) == 1
      assert graph.crs == "EPSG:4326"
    end

    test "ingests single Feature" do
      json = ~s"""
      {"type":"Feature","geometry":{"type":"Point","coordinates":[-74.0,40.7]},"properties":{"city":"NYC"}}
      """

      assert {:ok, graph} = GeoJSON.from_string(json)
      assert Graph.node_count(graph) == 1
      assert Graph.edge_count(graph) == 0
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = GeoJSON.from_string("not json")
    end

    test "returns error for unsupported type" do
      json = ~s|{"type":"GeometryCollection","geometries":[]}|
      assert {:error, _} = GeoJSON.from_string(json)
    end
  end

  describe "from_string!/2" do
    test "raises on invalid JSON" do
      assert_raise ArgumentError, fn ->
        GeoJSON.from_string!("bad")
      end
    end
  end

  describe "from_map/2" do
    test "ingests raw geometry" do
      geom = %{"type" => "Point", "coordinates" => [0, 0]}
      graph = GeoJSON.from_map(geom)
      assert Graph.node_count(graph) == 1
    end
  end
end
