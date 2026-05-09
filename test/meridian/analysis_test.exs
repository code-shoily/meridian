defmodule Meridian.AnalysisTest do
  use ExUnit.Case, async: true

  alias Meridian.{Analysis, Graph}

  doctest Meridian.Analysis

  # ---------------------------------------------------------------------------
  # diameter/2
  # ---------------------------------------------------------------------------

  describe "diameter/2" do
    test "empty graph returns nil" do
      assert Analysis.diameter(Graph.new()) == nil
    end

    test "single node graph returns zero-distance self-pair" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})

      result = Analysis.diameter(g)
      assert result.from == :a
      assert result.to == :a
      assert result.distance_m == 0
      assert result.path == [:a]
    end

    test "two-node graph: diameter is the edge weight" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)

      result = Analysis.diameter(g)
      assert result.from == :a
      assert result.to == :b
      assert result.distance_m > 110_000 and result.distance_m < 113_000
      assert result.path == [:a, :b]
    end

    test "linear path: diameter is the two endpoints" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 2.0}}})
        |> Graph.add_node(:d, %{geometry: %Geo.Point{coordinates: {0.0, 3.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)
        |> Graph.add_edge_ensure(:c, :d, nil)

      result = Analysis.diameter(g)
      assert result.from == :a
      assert result.to == :d
      assert result.distance_m > 330_000 and result.distance_m < 335_000
      assert result.path == [:a, :b, :c, :d]
    end

    test "cycle graph: diameter is the longest shortest path" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {1.0, 0.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {1.0, 1.0}}})
        |> Graph.add_node(:d, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)
        |> Graph.add_edge_ensure(:c, :d, nil)
        |> Graph.add_edge_ensure(:d, :a, nil)

      result = Analysis.diameter(g)
      # In a square cycle, diameter is two edges (a->b->c or a->d->c)
      assert result.distance_m > 220_000 and result.distance_m < 225_000
      assert result.from in [:a, :b, :c, :d]
      assert result.to in [:a, :b, :c, :d]
      assert result.from != result.to
      assert length(result.path) == 3
    end

    test "disconnected graph returns nil" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {1.0, 0.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {2.0, 0.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)

      assert Analysis.diameter(g) == nil
    end

    test "custom weight function overrides default" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 2.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)

      weight_fn = fn _g, _f, _t, _data -> 10.0 end

      result = Analysis.diameter(g, weight_fn: weight_fn)
      assert result.distance_m == 20.0
      assert result.path == [:a, :b, :c]
    end

    test "weight function returning nil skips edge" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {1.0, 0.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {2.0, 0.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)

      # Skip the a->b edge; graph becomes disconnected
      weight_fn = fn _g, f, _t, _data -> if f == :a, do: nil, else: 1.0 end

      assert Analysis.diameter(g, weight_fn: weight_fn) == nil
    end

    test "weight function returning :infinity skips edge" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {1.0, 0.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {2.0, 0.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)

      # Block the b->c edge; graph becomes disconnected
      weight_fn = fn _g, f, _t, _data -> if f == :b, do: :infinity, else: 1.0 end

      assert Analysis.diameter(g, weight_fn: weight_fn) == nil
    end

    test "graph without geometries uses unit weights" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{})
        |> Graph.add_node(:b, %{})
        |> Graph.add_node(:c, %{})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)

      result = Analysis.diameter(g)
      assert result.distance_m == 2.0
      assert result.path == [:a, :b, :c]
    end

    test "star graph: diameter is between any two leaves" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:center, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:leaf1, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_node(:leaf2, %{geometry: %Geo.Point{coordinates: {1.0, 0.0}}})
        |> Graph.add_node(:leaf3, %{geometry: %Geo.Point{coordinates: {0.0, -1.0}}})
        |> Graph.add_edge_ensure(:center, :leaf1, nil)
        |> Graph.add_edge_ensure(:center, :leaf2, nil)
        |> Graph.add_edge_ensure(:center, :leaf3, nil)

      result = Analysis.diameter(g)
      # Diameter is between the two farthest leaves (two edges)
      assert result.from != result.to
      assert result.from in [:center, :leaf1, :leaf2, :leaf3]
      assert result.to in [:center, :leaf1, :leaf2, :leaf3]
      assert :center in result.path
      assert length(result.path) == 3
      assert result.distance_m > 220_000 and result.distance_m < 225_000
    end
  end

  # ---------------------------------------------------------------------------
  # average_edge_length/1
  # ---------------------------------------------------------------------------

  describe "average_edge_length/1" do
    test "empty graph returns 0.0" do
      assert Analysis.average_edge_length(Graph.new()) == 0.0
    end

    test "graph with no geometries returns 0.0" do
      g =
        Graph.new()
        |> Graph.add_node(:a, %{foo: :bar})
        |> Graph.add_node(:b, %{baz: :qux})
        |> Graph.add_edge_ensure(:a, :b, nil)

      assert Analysis.average_edge_length(g) == 0.0
    end

    test "graph with all geometries" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 2.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)

      avg = Analysis.average_edge_length(g)
      # Each edge is ~111,195m; average should be about the same
      assert avg > 110_000 and avg < 113_000
    end

    test "skips edges where one endpoint lacks geometry" do
      g =
        Graph.new(kind: :undirected)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_node(:c, %{foo: :bar})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)

      avg = Analysis.average_edge_length(g)
      # Only a->b is counted
      assert avg > 110_000 and avg < 113_000
    end

    test "directed graph" do
      g =
        Graph.new(kind: :directed)
        |> Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
        |> Graph.add_node(:c, %{geometry: %Geo.Point{coordinates: {0.0, 2.0}}})
        |> Graph.add_edge_ensure(:a, :b, nil)
        |> Graph.add_edge_ensure(:b, :c, nil)

      avg = Analysis.average_edge_length(g)
      assert avg > 110_000 and avg < 113_000
    end
  end
end
