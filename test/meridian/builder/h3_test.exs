defmodule Meridian.Builder.H3Test do
  use ExUnit.Case, async: true

  alias Meridian.Builder.H3
  alias Meridian.Graph

  doctest Meridian.Builder.H3

  describe "grid/2" do
    test "creates a hex grid" do
      g =
        Graph.new(kind: :undirected)
        |> H3.grid(center: {37.7749, -122.4194}, resolution: 5, k_ring: 1)

      assert Graph.node_count(g) == 7
      assert Graph.kind(g) == :undirected
    end

    test "k_ring 0 returns only center" do
      g =
        Graph.new(kind: :undirected)
        |> H3.grid(center: {0.0, 0.0}, resolution: 3, k_ring: 0)

      assert Graph.node_count(g) == 1
    end

    test "raises on invalid resolution" do
      assert_raise ArgumentError, fn ->
        Graph.new() |> H3.grid(center: {0, 0}, resolution: 16)
      end
    end

    test "raises on invalid topology" do
      assert_raise ArgumentError, fn ->
        Graph.new() |> H3.grid(center: {0, 0}, resolution: 5, topology: :bogus)
      end
    end
  end
end
