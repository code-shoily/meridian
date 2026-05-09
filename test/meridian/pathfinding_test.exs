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
  end
end
