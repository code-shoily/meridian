defmodule Meridian.MultiGraphTest do
  use ExUnit.Case, async: true

  alias Meridian.{Graph, MultiGraph}

  doctest Meridian.MultiGraph

  describe "construction" do
    test "new/1 defaults" do
      g = MultiGraph.new()
      assert g.crs == "EPSG:4326"
      assert g.srid == 4326
      assert g.graph.kind == :directed
      assert g.bounds == nil
    end

    test "new/1 with options" do
      g = MultiGraph.new(kind: :undirected, crs: "EPSG:3857", srid: 3857)
      assert g.crs == "EPSG:3857"
      assert g.srid == 3857
      assert g.graph.kind == :undirected
    end

    test "from_yog/2" do
      yog = Yog.Multi.directed()
      g = MultiGraph.from_yog(yog, crs: "EPSG:3857")
      assert g.crs == "EPSG:3857"
      assert g.graph.kind == :directed
    end
  end

  describe "nodes" do
    test "add_node/3 and node/2" do
      g = MultiGraph.new() |> MultiGraph.add_node(:a, %{name: "A"})
      assert MultiGraph.node(g, :a) == %{name: "A"}
    end

    test "add_nodes/2" do
      g = MultiGraph.new() |> MultiGraph.add_nodes(a: 1, b: 2)
      assert MultiGraph.node_count(g) == 2
    end

    test "remove_node/2 removes edges" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, 1)
      g = MultiGraph.remove_node(g, :a)
      assert MultiGraph.node_count(g) == 1
      assert MultiGraph.edge_count(g) == 0
    end

    test "has_node?/2" do
      g = MultiGraph.new() |> MultiGraph.add_node(:a, %{})
      assert MultiGraph.has_node?(g, :a)
      refute MultiGraph.has_node?(g, :b)
    end
  end

  describe "edges" do
    test "add_edge/4 returns edge_id" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, eid} = MultiGraph.add_edge(g, :a, :b, %{mode: :walk})
      assert eid == 0

      {g, eid2} = MultiGraph.add_edge(g, :a, :b, %{mode: :cycle})
      assert eid2 == 1
      assert MultiGraph.edge_count(g) == 2
    end

    test "remove_edge/2" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, eid} = MultiGraph.add_edge(g, :a, :b, 1)
      g = MultiGraph.remove_edge(g, eid)
      assert MultiGraph.edge_count(g) == 0
      refute MultiGraph.has_edge?(g, eid)
    end

    test "edges_between/3" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, %{mode: :walk})
      {g, _} = MultiGraph.add_edge(g, :a, :b, %{mode: :cycle})

      between = MultiGraph.edges_between(g, :a, :b)
      assert length(between) == 2
      modes = Enum.map(between, fn {_eid, data} -> data.mode end)
      assert :walk in modes
      assert :cycle in modes
    end

    test "edge_count/3" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, 1)
      {g, _} = MultiGraph.add_edge(g, :a, :b, 2)
      assert MultiGraph.edge_count(g, :a, :b) == 2
    end
  end

  describe "to_simple/2" do
    test ":first keeps first edge" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, 10)
      {g, _} = MultiGraph.add_edge(g, :a, :b, 3)

      simple = MultiGraph.to_simple(g, :first)
      assert Graph.edge_count(simple) == 1
      [{_, _, weight}] = Graph.edges(simple)
      assert weight == 10
    end

    test ":min_weight" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, 10)
      {g, _} = MultiGraph.add_edge(g, :a, :b, 3)

      simple = MultiGraph.to_simple(g, :min_weight)
      [{_, _, weight}] = Graph.edges(simple)
      assert weight == 3
    end

    test ":max_weight" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, 10)
      {g, _} = MultiGraph.add_edge(g, :a, :b, 3)

      simple = MultiGraph.to_simple(g, :max_weight)
      [{_, _, weight}] = Graph.edges(simple)
      assert weight == 10
    end

    test "{:combine, combiner}" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, 10)
      {g, _} = MultiGraph.add_edge(g, :a, :b, 3)

      simple = MultiGraph.to_simple(g, {:combine, &Kernel.+/2})
      [{_, _, weight}] = Graph.edges(simple)
      assert weight == 13
    end

    test "{:mode, key} selects matching edges" do
      g =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, %{mode: :walk, minutes: 20})
      {g, _} = MultiGraph.add_edge(g, :a, :b, %{mode: :cycle, minutes: 5})

      simple = MultiGraph.to_simple(g, {:mode, :cycle})
      [{_, _, data}] = Graph.edges(simple)
      assert data.mode == :cycle
      assert data.minutes == 5
    end

    test "preserves CRS and metadata" do
      g =
        MultiGraph.new(crs: "EPSG:3857", srid: 3857)
        |> MultiGraph.add_node(:a, %{})
        |> MultiGraph.add_node(:b, %{})

      {g, _} = MultiGraph.add_edge(g, :a, :b, 1)
      simple = MultiGraph.to_simple(g, :first)
      assert simple.crs == "EPSG:3857"
      assert simple.srid == 3857
    end
  end

  describe "merge/2" do
    test "merges two multigraphs" do
      a = MultiGraph.new() |> MultiGraph.add_node(1, %{x: 1})
      b = MultiGraph.new() |> MultiGraph.add_node(2, %{x: 2})
      merged = MultiGraph.merge(a, b)
      assert MultiGraph.node_count(merged) == 2
    end

    test "raises on CRS mismatch" do
      a = MultiGraph.new(crs: "EPSG:4326")
      b = MultiGraph.new(crs: "EPSG:3857")

      assert_raise ArgumentError, ~r/cannot merge graphs with different CRS/, fn ->
        MultiGraph.merge(a, b)
      end
    end
  end

  describe "protocols" do
    test "Enumerable" do
      g = MultiGraph.new() |> MultiGraph.add_nodes(a: 1, b: 2)
      assert Enum.count(g) == 2
      assert Enum.to_list(g) |> Enum.sort() == [{:a, 1}, {:b, 2}]
    end

    test "Inspect" do
      g = MultiGraph.new() |> MultiGraph.add_node(:a, %{})
      inspected = inspect(g)
      assert inspected =~ "MultiGraph"
      assert inspected =~ "nodes: 1"
    end
  end

  describe "realistic multi-modal routing" do
    test "finds fastest mode per segment then routes" do
      # Build a multi-modal street network
      g =
        MultiGraph.new(kind: :undirected)
        |> MultiGraph.add_node(:home, %{geometry: %Geo.Point{coordinates: {-74.0, 40.7}}})
        |> MultiGraph.add_node(:park, %{geometry: %Geo.Point{coordinates: {-74.01, 40.71}}})
        |> MultiGraph.add_node(:work, %{geometry: %Geo.Point{coordinates: {-74.02, 40.72}}})

      # home -> park: walk (15 min) and cycle (5 min)
      {g, _} = MultiGraph.add_edge(g, :home, :park, %{mode: :walk, minutes: 15})
      {g, _} = MultiGraph.add_edge(g, :home, :park, %{mode: :cycle, minutes: 5})

      # park -> work: walk (10 min) and cycle (3 min)
      {g, _} = MultiGraph.add_edge(g, :park, :work, %{mode: :walk, minutes: 10})
      {g, _} = MultiGraph.add_edge(g, :park, :work, %{mode: :cycle, minutes: 3})

      # direct home -> work: drive only (12 min)
      {g, _} = MultiGraph.add_edge(g, :home, :work, %{mode: :drive, minutes: 12})

      # Collapse to simple graph selecting fastest per segment
      simple =
        MultiGraph.to_simple(
          g,
          {:by,
           fn edges ->
             edges |> Enum.min_by(fn {_eid, _f, _t, data} -> data.minutes end)
           end}
        )

      # Route by minutes
      weight_fn = fn _g, _f, _t, data -> data.minutes end

      {:ok, path} =
        Meridian.Pathfinding.shortest_path(simple,
          from: :home,
          to: :work,
          weight_fn: weight_fn
        )

      # home -> park -> work = 5 + 3 = 8 minutes, faster than direct drive (12)
      assert path.nodes == [:home, :park, :work]
      assert path.weight == 8
    end
  end
end
