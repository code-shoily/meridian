defmodule MockPBFParser do
  def stream(_path) do
    [:header, :primitive_block]
  end

  def decompress_block(:primitive_block), do: :decompressed_block

  def decode_block(:decompressed_block) do
    [
      %PBFParser.Data.Node{id: 1, latitude: 43.6426, longitude: -79.3871, tags: %{}},
      %PBFParser.Data.Node{id: 2, latitude: 43.6450, longitude: -79.3850, tags: %{}},
      %PBFParser.Data.Node{id: 3, latitude: 43.6480, longitude: -79.3830, tags: %{}},
      %PBFParser.Data.Way{
        id: 10,
        refs: [1, 2, 3],
        tags: %{"highway" => "primary", "name" => "Yonge St"}
      }
    ]
  end
end

defmodule Meridian.Builder.OSMTest do
  use ExUnit.Case, async: true

  alias Meridian.Builder.OSM, as: OSMBuilder
  alias Meridian.Graph

  describe "from_overpass_json/2" do
    test "correctly parses and splits ways at intersections" do
      # Mock Overpass data with two intersecting ways:
      # Way 10: 1 - 2 - 3 (bidirectional)
      # Way 11: 2 - 4 (oneway forward)
      elements = [
        %{"type" => "node", "id" => 1, "lat" => 43.6426, "lon" => -79.3871, "tags" => %{}},
        %{"type" => "node", "id" => 2, "lat" => 43.6450, "lon" => -79.3850, "tags" => %{}},
        %{"type" => "node", "id" => 3, "lat" => 43.6480, "lon" => -79.3830, "tags" => %{}},
        %{"type" => "node", "id" => 4, "lat" => 43.6460, "lon" => -79.3840, "tags" => %{}},
        %{
          "type" => "way",
          "id" => 10,
          "nodes" => [1, 2, 3],
          "tags" => %{
            "highway" => "primary",
            "name" => "Yonge St"
          }
        },
        %{
          "type" => "way",
          "id" => 11,
          "nodes" => [2, 4],
          "tags" => %{
            "highway" => "residential",
            "name" => "Bay St",
            "oneway" => "yes"
          }
        }
      ]

      data = %{"elements" => elements}

      assert {:ok, g} = OSMBuilder.from_overpass_json(data)

      # All 4 nodes should be in the graph since node 2 is an intersection
      assert Graph.node_count(g) == 4

      # Edges:
      # 1 <-> 2 (2 directed edges)
      # 2 <-> 3 (2 directed edges)
      # 2 -> 4 (1 directed edge)
      # Total directed edges = 5
      assert Graph.edge_count(g) == 5

      # Check specific edges
      assert Map.has_key?(g.graph.out_edges[1], 2)
      assert Map.has_key?(g.graph.out_edges[2], 1)
      assert Map.has_key?(g.graph.out_edges[2], 3)
      assert Map.has_key?(g.graph.out_edges[3], 2)
      assert Map.has_key?(g.graph.out_edges[2], 4)
      refute Map.get(g.graph.out_edges, 4, %{}) |> Map.has_key?(2)

      # Check edge weights (distances in meters)
      edge_1_2 = g.graph.out_edges[1][2]
      assert edge_1_2.distance_m > 0
      assert edge_1_2.name == "Yonge St"
      assert edge_1_2.highway == "primary"
      refute edge_1_2.oneway

      edge_2_4 = g.graph.out_edges[2][4]
      assert edge_2_4.oneway
      assert edge_2_4.name == "Bay St"
    end

    test "handles oneway=-1 by reversing direction" do
      elements = [
        %{"type" => "node", "id" => 1, "lat" => 43.6426, "lon" => -79.3871, "tags" => %{}},
        %{"type" => "node", "id" => 2, "lat" => 43.6450, "lon" => -79.3850, "tags" => %{}},
        %{
          "type" => "way",
          "id" => 10,
          "nodes" => [1, 2],
          "tags" => %{
            "highway" => "primary",
            "name" => "One-Way Reverse",
            "oneway" => "-1"
          }
        }
      ]

      data = %{"elements" => elements}

      assert {:ok, g} = OSMBuilder.from_overpass_json(data)
      assert Graph.node_count(g) == 2
      assert Graph.edge_count(g) == 1

      # Edge should go from 2 to 1 (reversed)
      assert Map.has_key?(g.graph.out_edges[2], 1)
      refute Map.get(g.graph.out_edges, 1, %{}) |> Map.has_key?(2)
    end

    test "respects oneway_as_directed: false option" do
      elements = [
        %{"type" => "node", "id" => 1, "lat" => 43.6426, "lon" => -79.3871, "tags" => %{}},
        %{"type" => "node", "id" => 2, "lat" => 43.6450, "lon" => -79.3850, "tags" => %{}},
        %{
          "type" => "way",
          "id" => 10,
          "nodes" => [1, 2],
          "tags" => %{
            "highway" => "primary",
            "name" => "Oneway Way",
            "oneway" => "yes"
          }
        }
      ]

      data = %{"elements" => elements}

      assert {:ok, g} = OSMBuilder.from_overpass_json(data, oneway_as_directed: false)
      assert Graph.node_count(g) == 2
      # Should be bidirectional because option is false
      assert Graph.edge_count(g) == 2
      assert Map.has_key?(g.graph.out_edges[1], 2)
      assert Map.has_key?(g.graph.out_edges[2], 1)
    end

    test "filters by highway type" do
      elements = [
        %{"type" => "node", "id" => 1, "lat" => 43.6426, "lon" => -79.3871, "tags" => %{}},
        %{"type" => "node", "id" => 2, "lat" => 43.6450, "lon" => -79.3850, "tags" => %{}},
        %{"type" => "node", "id" => 3, "lat" => 43.6480, "lon" => -79.3830, "tags" => %{}},
        %{
          "type" => "way",
          "id" => 10,
          "nodes" => [1, 2],
          "tags" => %{
            "highway" => "primary"
          }
        },
        %{
          "type" => "way",
          "id" => 11,
          "nodes" => [2, 3],
          "tags" => %{
            "highway" => "service"
          }
        }
      ]

      data = %{"elements" => elements}

      # Defaults should filter out "service"
      assert {:ok, g} = OSMBuilder.from_overpass_json(data)
      assert Graph.node_count(g) == 2
      assert Graph.edge_count(g) == 2
      assert Map.has_key?(g.graph.out_edges[1], 2)
      refute Map.has_key?(g.graph.out_edges[2], 3)
    end

    test "handles empty bbox elements" do
      data = %{"elements" => []}
      assert {:ok, g} = OSMBuilder.from_overpass_json(data)
      assert Graph.node_count(g) == 0
      assert Graph.edge_count(g) == 0
      assert is_nil(g.bounds)
    end
  end

  describe "from_bbox/1 validation" do
    test "raises on invalid southwest/northeast coordinates" do
      assert_raise ArgumentError, fn ->
        OSMBuilder.from_bbox(sw: {45.0, -79.0}, ne: {43.0, -79.0})
      end

      assert_raise ArgumentError, fn ->
        OSMBuilder.from_bbox(sw: {43.0, -79.0}, ne: {44.0, -80.0})
      end
    end
  end

  describe "from_pbf/2" do
    test "streams and builds graph from PBF file" do
      assert {:ok, g} = OSMBuilder.from_pbf("fake.osm.pbf", parser_module: MockPBFParser)

      # 1 and 3 are endpoints, node 2 is an intermediate node and should be dropped
      assert Graph.node_count(g) == 2
      assert Graph.edge_count(g) == 2
      assert Map.has_key?(g.graph.out_edges[1], 3)
      assert Map.has_key?(g.graph.out_edges[3], 1)
      refute Map.get(g.graph.out_edges, 2, %{}) |> Map.has_key?(1)
    end

    test "streams and builds native Zog ResourceGraph from PBF file" do
      assert {:ok, %{graph: res_graph, x_coords: x_coords, y_coords: y_coords}} =
               OSMBuilder.from_pbf("fake.osm.pbf",
                 parser_module: MockPBFParser,
                 output: :resource_graph
               )

      assert is_map(res_graph)
      assert Map.has_key?(res_graph, :resource)
      assert Map.has_key?(res_graph, :builder)
      assert is_map(x_coords)
      assert is_map(y_coords)
      assert Map.keys(x_coords) == [1, 3]
      assert Map.keys(y_coords) == [1, 3]

      # Check coordinates
      assert x_coords[1] == -79.3871
      assert y_coords[1] == 43.6426

      # Check native properties
      assert Zog.node_count(res_graph.builder) == 2
      assert Zog.edge_count(res_graph.builder) == 2

      # Cleanup NIF resource
      Zog.ResourceGraph.destroy(res_graph)
    end
  end
end
