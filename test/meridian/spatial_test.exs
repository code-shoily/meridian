defmodule Meridian.SpatialTest do
  use ExUnit.Case, async: true

  alias Meridian.{Graph, Spatial}

  doctest Meridian.Spatial

  describe "within/3" do
    test "returns nodes within radius" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 0.1}}})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      results = Spatial.within(g, point, radius: 2_000)

      ids = Enum.map(results, fn {id, _} -> id end) |> Enum.sort()
      assert ids == [:a, :b]
    end

    test "returns empty list when nothing is within radius" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      point = %Geo.Point{coordinates: {0.0, 1.0}}
      results = Spatial.within(g, point, radius: 100)

      assert results == []
    end

    test "skips nodes without geometry" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{foo: 1})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      results = Spatial.within(g, point, radius: 2_000)

      ids = Enum.map(results, fn {id, _} -> id end)
      assert ids == [:a]
    end

    test "include_distance option" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      results = Spatial.within(g, point, radius: 2_000, include_distance: true)

      assert length(results) == 2
      [{:a, _, d1}, {:b, _, d2}] = results
      assert d1 == 0.0
      assert d2 > 1_100 and d2 < 1_120
    end

    test "filter option" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}, type: :shop})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}, type: :park})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 0.02}}, type: :park})

      point = %Geo.Point{coordinates: {0.0, 0.0}}

      results =
        Spatial.within(g, point,
          radius: 2_500,
          filter: fn _id, data -> data.type == :park end
        )

      ids = Enum.map(results, fn {id, _} -> id end) |> Enum.sort()
      assert ids == [:b, :c]
    end

    test "euclidean metric" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {3.0, 4.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {10.0, 0.0}}})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      results = Spatial.within(g, point, radius: 6.0, metric: :euclidean)

      ids = Enum.map(results, fn {id, _} -> id end) |> Enum.sort()
      assert ids == [:a, :b]
    end
  end

  describe "nearest/3" do
    test "returns n nearest nodes" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 0.1}}})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      results = Spatial.nearest(g, point, n: 2)

      ids = Enum.map(results, fn {id, _, _} -> id end)
      assert ids == [:a, :b]
    end

    test "returns distances" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      [{_, _, d1}, {_, _, d2}] = Spatial.nearest(g, point, n: 2)

      assert d1 == 0.0
      assert d2 > 1_100 and d2 < 1_120
    end

    test "skips nodes without geometry" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{foo: 1})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      results = Spatial.nearest(g, point, n: 2)

      ids = Enum.map(results, fn {id, _, _} -> id end)
      assert ids == [:a]
    end

    test "filter option" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}, type: :shop})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 0.01}}, type: :park})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 0.02}}, type: :park})

      point = %Geo.Point{coordinates: {0.0, 0.0}}

      results =
        Spatial.nearest(g, point,
          n: 2,
          filter: fn _id, data -> data.type == :park end
        )

      ids = Enum.map(results, fn {id, _, _} -> id end)
      assert ids == [:b, :c]
    end

    test "euclidean metric" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {10.0, 10.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {3.0, 4.0}}})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      [{_, _, d}] = Spatial.nearest(g, point, n: 1, metric: :euclidean)

      assert d == 5.0
    end

    test "n larger than node count returns all" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      point = %Geo.Point{coordinates: {0.0, 0.0}}
      results = Spatial.nearest(g, point, n: 100)

      assert length(results) == 1
    end

    test "raises on unknown metric" do
      g = Graph.new() |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      point = %Geo.Point{coordinates: {0.0, 0.0}}

      assert_raise ArgumentError, ~r/unknown metric/, fn ->
        Spatial.nearest(g, point, n: 1, metric: :foobar)
      end
    end
  end
end
