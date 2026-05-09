defmodule Meridian.CRSTest do
  use ExUnit.Case, async: true

  alias Meridian.{CRS, Graph}

  doctest Meridian.CRS

  describe "distance/3" do
    test "returns haversine distance in meters" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})

      dist = CRS.distance(g, :a, :b)
      assert is_float(dist)
      assert dist > 110_000 and dist < 112_000
    end

    test "returns nil for missing geometry" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})

      assert CRS.distance(g, :a, :b) == nil
    end
  end

  describe "compute_edge_weights/2" do
    test "replaces edge weights with distances" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> CRS.compute_edge_weights()

      [{:a, :b, weight}] = Graph.edges(g)
      assert weight > 110_000 and weight < 112_000
    end

    test "respects :round option" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> CRS.compute_edge_weights(round: 0)

      [{:a, :b, weight}] = Graph.edges(g)
      assert weight == 111_195.0
    end
  end

  describe "same_crs?/2" do
    test "returns true for matching CRS" do
      a = Graph.new(crs: "EPSG:4326")
      b = Graph.new(crs: "EPSG:4326")
      assert CRS.same_crs?(a, b)
    end

    test "returns false for different CRS" do
      a = Graph.new(crs: "EPSG:4326")
      b = Graph.new(crs: "EPSG:3857")
      refute CRS.same_crs?(a, b)
    end
  end

  describe "bbox/1" do
    test "returns bounds as tuple" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {2.0, 3.0}}})
        |> Graph.recompute_bounds()

      {min_x, min_y, max_x, max_y} = CRS.bbox(g)
      assert min_x == 0.0
      assert min_y == 0.0
      assert max_x == 2.0
      assert max_y == 3.0
    end

    test "returns nil when no bounds" do
      g = Graph.new()
      assert CRS.bbox(g) == nil
    end
  end
end
