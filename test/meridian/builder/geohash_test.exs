defmodule Meridian.Builder.GeohashTest do
  use ExUnit.Case, async: true

  alias Meridian.Builder.Geohash, as: GeohashBuilder
  alias Meridian.Graph

  doctest Meridian.Builder.Geohash

  describe "grid/2" do
    test "creates nodes for a small bbox" do
      g =
        Graph.new(kind: :undirected)
        |> GeohashBuilder.grid(sw: {0.0, 0.0}, ne: {0.05, 0.05}, precision: 5)

      assert Graph.node_count(g) >= 1

      for {_id, data} <- Graph.nodes(g) do
        assert is_binary(data.geohash)
        assert data.geohash_precision == 5
        assert %Geo.Point{} = data.geometry
      end
    end

    test "rook topology creates edges between neighbors" do
      g =
        Graph.new(kind: :undirected)
        |> GeohashBuilder.grid(sw: {0.0, 0.0}, ne: {6.0, 6.0}, precision: 3, topology: :rook)

      assert Graph.edge_count(g) >= 1
    end

    test "raises on invalid precision" do
      assert_raise ArgumentError, fn ->
        Graph.new() |> GeohashBuilder.grid(sw: {0, 0}, ne: {1, 1}, precision: 0)
      end
    end

    test "raises on invalid topology" do
      assert_raise ArgumentError, fn ->
        Graph.new() |> GeohashBuilder.grid(sw: {0, 0}, ne: {1, 1}, precision: 3, topology: :bogus)
      end
    end
  end

  describe "encode/decode via geohash library" do
    test "roundtrip" do
      hash = Geohash.encode(40.7484, -73.9857, 6)
      assert String.length(hash) == 6

      {lat, lon} = Geohash.decode(hash)
      assert_in_delta lat, 40.7484, 0.5
      assert_in_delta lon, -73.9857, 0.5
    end
  end
end
