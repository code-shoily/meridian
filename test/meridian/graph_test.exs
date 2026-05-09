defmodule Meridian.GraphTest do
  use ExUnit.Case, async: true

  alias Meridian.Graph

  doctest Meridian.Graph

  describe "new/1" do
    test "defaults to WGS-84 and directed" do
      g = Graph.new()
      assert g.crs == "EPSG:4326"
      assert g.srid == 4326
      assert g.graph.kind == :directed
      assert g.bounds == nil
    end

    test "accepts overrides" do
      g = Graph.new(kind: :undirected, crs: "EPSG:3857", srid: 3857)
      assert g.graph.kind == :undirected
      assert g.crs == "EPSG:3857"
      assert g.srid == 3857
    end
  end

  describe "from_yog/2 and to_yog/1" do
    test "roundtrip" do
      yog = Yog.undirected() |> Yog.add_edge_ensure(1, 2, 10)
      g = Graph.from_yog(yog, crs: "EPSG:4326")
      assert g.graph == yog
      assert Graph.to_yog(g) == yog
      assert Graph.node_count(g) == 2
    end
  end

  describe "queries" do
    test "nodes, edges, node, has_node?, has_geometry?, kind" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}, name: "A"})
        |> Graph.add_node(:b, %{name: "B"})
        |> Graph.add_edge_ensure(:a, :b, 10)

      assert map_size(Graph.nodes(g)) == 2
      assert length(Graph.edges(g)) == 1
      assert Graph.node(g, :a).name == "A"
      assert Graph.has_node?(g, :a)
      refute Graph.has_node?(g, :c)
      assert Graph.has_geometry?(g, :a)
      refute Graph.has_geometry?(g, :b)
      assert Graph.kind(g) == :directed
    end
  end

  describe "add_node/3 and add_nodes/2" do
    test "stores spatial data" do
      g =
        Graph.new()
        |> Graph.add_node(:nyc, %{geometry: %Geo.Point{coordinates: {-74.0, 40.7}}})

      assert Graph.node(g, :nyc).geometry.coordinates == {-74.0, 40.7}
    end

    test "batch insert from keyword list" do
      g =
        Graph.new()
        |> Graph.add_nodes(a: %{name: "A"}, b: %{name: "B"})

      assert Graph.node_count(g) == 2
    end
  end

  describe "update_node/3" do
    test "merges data into existing node" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{name: "A"})
        |> Graph.update_node(:a, %{tags: [:highway]})

      assert Graph.node(g, :a).name == "A"
      assert Graph.node(g, :a).tags == [:highway]
    end

    test "creates node if it does not exist" do
      g = Graph.new() |> Graph.update_node(:a, %{name: "A"})
      assert Graph.node(g, :a).name == "A"
    end
  end

  describe "add_edge/4 and add_edge!/4" do
    test "adds weighted edges" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})

      assert {:ok, g} = Graph.add_edge(g, :a, :b, %{distance: 5.0})
      assert [{:a, :b, %{distance: 5.0}}] == Graph.edges(g)
    end

    test "returns error for missing nodes" do
      g = Graph.new()
      assert {:error, _} = Graph.add_edge(g, :a, :b, 1)
    end

    test "bang variant raises on error" do
      g = Graph.new()
      assert_raise ArgumentError, fn -> Graph.add_edge!(g, :a, :b, 1) end
    end
  end

  describe "remove_node/2 and remove_edge/3" do
    test "removes node and edges" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})
        |> Graph.add_edge_ensure(:a, :b, 1)
        |> Graph.remove_node(:a)

      refute Graph.has_node?(g, :a)
      assert Graph.edge_count(g) == 0
    end

    test "remove_edge/3 removes single edge" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})
        |> Graph.add_edge_ensure(:a, :b, 1)
        |> Graph.remove_edge(:a, :b)

      assert Graph.edge_count(g) == 0
    end
  end

  describe "recompute_bounds/1" do
    test "computes bounding box from nodes" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {2.0, 3.0}}})
        |> Graph.recompute_bounds()

      assert %Geo.Polygon{} = g.bounds
    end
  end

  describe "merge/2" do
    test "combines two graphs with same CRS" do
      a = Graph.new() |> Graph.add_node(1, %{name: "A"})
      b = Graph.new() |> Graph.add_node(2, %{name: "B"}) |> Graph.add_edge_ensure(2, 1, 5)
      merged = Graph.merge(a, b)

      assert Graph.node_count(merged) == 2
      assert Graph.edge_count(merged) == 1
    end

    test "raises on CRS mismatch" do
      a = Graph.new(crs: "EPSG:4326")
      b = Graph.new(crs: "EPSG:3857")

      assert_raise ArgumentError, fn ->
        Graph.merge(a, b)
      end
    end
  end

  describe "Enumerable protocol" do
    test "count, member?, reduce, slice" do
      g =
        Graph.new()
        |> Graph.add_node(1, "A")
        |> Graph.add_node(2, "B")

      assert Enum.count(g) == 2
      assert Enum.member?(g, {1, "A"})
      refute Enum.member?(g, {1, "Z"})
      assert Enum.to_list(g) |> Enum.sort() == [{1, "A"}, {2, "B"}]
      assert Enum.slice(g, 0, 1) |> length() == 1
    end
  end

  describe "Inspect protocol" do
    test "pretty-prints with stats" do
      g = Graph.new() |> Graph.add_node(1, "A")
      assert inspect(g) == "#Meridian.Graph<EPSG:4326, 1 node, 0 edges>"

      g = Graph.new() |> Graph.add_node(1, "A") |> Graph.add_node(2, "B")
      assert inspect(g) == "#Meridian.Graph<EPSG:4326, 2 nodes, 0 edges>"
    end
  end
end
