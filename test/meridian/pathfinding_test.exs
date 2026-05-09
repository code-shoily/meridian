defmodule Meridian.PathfindingTest do
  use ExUnit.Case, async: true

  alias Meridian.{Graph, Pathfinding}

  doctest Meridian.Pathfinding

  describe "a_star/2" do
    test "finds shortest path on simple graph" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_edge_ensure(:a, :b, 100.0)

      assert {:ok, path} = Pathfinding.a_star(g, from: :a, to: :b)
      assert path.nodes == [:a, :b]
    end

    test "raises on missing start node" do
      g = Graph.new() |> Graph.add_node(:a, %{})

      assert_raise ArgumentError, fn ->
        Pathfinding.a_star(g, from: :missing, to: :a)
      end
    end

    test "raises on missing goal node" do
      g = Graph.new() |> Graph.add_node(:a, %{})

      assert_raise ArgumentError, fn ->
        Pathfinding.a_star(g, from: :a, to: :missing)
      end
    end

    test "skips edges with :infinity weight" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})
        |> Graph.add_node(:c, %{})
        |> Graph.add_edge_ensure(:a, :b, %{distance: 1, status: :open})
        |> Graph.add_edge_ensure(:b, :c, %{distance: 1, status: :closed})
        |> Graph.add_edge_ensure(:a, :c, %{distance: 5, status: :open})

      weight_fn = fn _g, _f, _t, data ->
        if data.status == :closed, do: :infinity, else: data.distance
      end

      assert {:ok, path} = Pathfinding.a_star(g, from: :a, to: :c, weight_fn: weight_fn)
      assert path.nodes == [:a, :c]
    end

    test "skips edges with nil weight" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})
        |> Graph.add_node(:c, %{})
        |> Graph.add_edge_ensure(:a, :b, 1)
        |> Graph.add_edge_ensure(:b, :c, 1)
        |> Graph.add_edge_ensure(:a, :c, 5)

      weight_fn = fn _g, _f, _t, data -> if data > 2, do: nil, else: data end

      assert {:ok, path} = Pathfinding.a_star(g, from: :a, to: :c, weight_fn: weight_fn)
      assert path.nodes == [:a, :b, :c]
    end

    test "filters out nodes with node_filter" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{closed?: false})
        |> Graph.add_node(:b, %{closed?: true})
        |> Graph.add_node(:c, %{closed?: false})
        |> Graph.add_edge_ensure(:a, :b, 1)
        |> Graph.add_edge_ensure(:b, :c, 1)
        |> Graph.add_edge_ensure(:a, :c, 10)

      node_filter = fn _id, data -> not data.closed? end
      weight_fn = fn _g, _f, _t, data -> data end

      assert {:ok, path} =
               Pathfinding.a_star(g,
                 from: :a,
                 to: :c,
                 weight_fn: weight_fn,
                 node_filter: node_filter
               )

      assert path.nodes == [:a, :c]
    end

    test "backward-compatible weight_fn with arity 3" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_edge_ensure(:a, :b, 999)

      weight_fn = fn graph, from, to ->
        case Meridian.CRS.distance(graph, from, to) do
          nil -> 1.0
          d -> d
        end
      end

      assert {:ok, path} = Pathfinding.a_star(g, from: :a, to: :b, weight_fn: weight_fn)
      assert path.nodes == [:a, :b]
    end
  end

  describe "shortest_path/2" do
    test "finds shortest path with Dijkstra" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})
        |> Graph.add_node(:c, %{})
        |> Graph.add_edge_ensure(:a, :b, 1)
        |> Graph.add_edge_ensure(:b, :c, 1)
        |> Graph.add_edge_ensure(:a, :c, 5)

      weight_fn = fn _g, _f, _t, data -> data end

      assert {:ok, path} = Pathfinding.shortest_path(g, from: :a, to: :c, weight_fn: weight_fn)
      assert path.nodes == [:a, :b, :c]
      assert path.weight == 2
    end

    test "respects node_filter" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{open: true})
        |> Graph.add_node(:b, %{open: false})
        |> Graph.add_node(:c, %{open: true})
        |> Graph.add_edge_ensure(:a, :b, 1)
        |> Graph.add_edge_ensure(:b, :c, 1)
        |> Graph.add_edge_ensure(:a, :c, 10)

      weight_fn = fn _g, _f, _t, data -> data end
      node_filter = fn _id, data -> data.open end

      assert {:ok, path} =
               Pathfinding.shortest_path(g,
                 from: :a,
                 to: :c,
                 weight_fn: weight_fn,
                 node_filter: node_filter
               )

      assert path.nodes == [:a, :c]
    end
  end

  describe "widest_path/2" do
    test "finds maximum bottleneck path" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})
        |> Graph.add_node(:c, %{})
        |> Graph.add_node(:d, %{})
        |> Graph.add_edge_ensure(:a, :b, 100)
        |> Graph.add_edge_ensure(:b, :d, 80)
        |> Graph.add_edge_ensure(:a, :c, 50)
        |> Graph.add_edge_ensure(:c, :d, 200)

      weight_fn = fn _g, _f, _t, data -> data end

      assert {:ok, path} = Pathfinding.widest_path(g, from: :a, to: :d, weight_fn: weight_fn)
      assert path.nodes == [:a, :b, :d]
      assert path.weight == 80
    end

    test "respects node_filter" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{open: true})
        |> Graph.add_node(:b, %{open: false})
        |> Graph.add_node(:c, %{open: true})
        |> Graph.add_node(:d, %{open: true})
        |> Graph.add_edge_ensure(:a, :b, 100)
        |> Graph.add_edge_ensure(:b, :d, 80)
        |> Graph.add_edge_ensure(:a, :c, 50)
        |> Graph.add_edge_ensure(:c, :d, 200)

      weight_fn = fn _g, _f, _t, data -> data end
      node_filter = fn _id, data -> data.open end

      assert {:ok, path} =
               Pathfinding.widest_path(g,
                 from: :a,
                 to: :d,
                 weight_fn: weight_fn,
                 node_filter: node_filter
               )

      assert path.nodes == [:a, :c, :d]
    end
  end
end
