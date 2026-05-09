defmodule Meridian.GeometryTest do
  use ExUnit.Case, async: true

  alias Meridian.Geometry

  doctest Meridian.Geometry

  describe "euclidean/2" do
    test "computes 2D distance" do
      a = %Geo.Point{coordinates: {0.0, 0.0}}
      b = %Geo.Point{coordinates: {3.0, 4.0}}
      assert Geometry.euclidean(a, b) == 5.0
    end
  end

  describe "contains?/2" do
    test "point in polygon" do
      poly = %Geo.Polygon{coordinates: [[{0, 0}, {10, 0}, {10, 10}, {0, 10}, {0, 0}]]}
      assert Geometry.contains?(poly, %Geo.Point{coordinates: {5, 5}})
      refute Geometry.contains?(poly, %Geo.Point{coordinates: {15, 5}})
    end
  end

  describe "geo_length/1" do
    test "haversine length of a line" do
      line = %Geo.LineString{coordinates: [{0.0, 0.0}, {0.0, 1.0}]}
      len = Geometry.geo_length(line)
      assert len > 110_000 and len < 112_000
    end

    test "zero for single coordinate" do
      line = %Geo.LineString{coordinates: [{0.0, 0.0}]}
      assert Geometry.geo_length(line) == 0.0
    end
  end

  describe "centroid/1" do
    test "arithmetic mean of vertices" do
      poly = %Geo.Polygon{coordinates: [[{0, 0}, {10, 0}, {10, 10}, {0, 10}, {0, 0}]]}
      assert Geometry.centroid(poly).coordinates == {5.0, 5.0}
    end
  end

  describe "envelope/1" do
    test "returns nil for empty graph" do
      assert Geometry.envelope(Yog.directed()) == nil
    end

    test "computes bbox from points" do
      g =
        Yog.directed()
        |> Yog.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Yog.add_node(:b, %{geometry: %Geo.Point{coordinates: {2.0, 3.0}}})

      poly = Geometry.envelope(g)
      assert %Geo.Polygon{} = poly
      [{min_x, min_y}, {max_x, _}, _, _, _] = hd(poly.coordinates)
      assert min_x == 0.0
      assert min_y == 0.0
      assert max_x == 2.0
    end
  end
end
