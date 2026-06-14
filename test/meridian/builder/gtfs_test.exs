defmodule Meridian.Builder.GTFSTest do
  use ExUnit.Case, async: true

  alias Meridian.Builder.GTFS, as: GTFSBuilder
  alias Meridian.Graph
  alias Meridian.Pathfinding

  # Helper to build a mock GTFS zip file in memory
  defp build_mock_gtfs_zip do
    stops = """
    stop_id,stop_name,stop_lat,stop_lon,zone_id
    stop_1,Union Station,43.6453,-79.3806,1
    stop_2,Spadina Station,43.6673,-79.4042,1
    stop_3,Kipling Station,43.6375,-79.5356,1
    stop_4,Long Branch Loop,43.5913,-79.5442,1
    """

    routes = """
    route_id,route_short_name,route_long_name,route_type
    route_1,1,Yonge-University,1
    route_2,501,Queen Streetcar,0
    route_3,300,Bloor-Danforth Night Bus,3
    """

    calendar = """
    service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
    service_weekday,1,1,1,1,1,0,0,20260501,20260531
    service_weekend,0,0,0,0,0,1,1,20260501,20260531
    """

    trips = """
    route_id,service_id,trip_id,trip_headsign
    route_1,service_weekday,trip_w_1,Downtown
    route_1,service_weekday,trip_w_2,Downtown
    route_2,service_weekday,trip_w_3,Long Branch
    route_2,service_weekend,trip_we_1,Long Branch
    """

    stop_times = """
    trip_id,arrival_time,departure_time,stop_id,stop_sequence
    trip_w_1,08:00:00,08:00:00,stop_1,1
    trip_w_1,08:15:00,08:15:00,stop_2,2
    trip_w_2,08:30:00,08:30:00,stop_1,1
    trip_w_2,08:45:00,08:45:00,stop_2,2
    trip_w_3,08:20:00,08:20:00,stop_2,1
    trip_w_3,08:37:00,08:37:00,stop_3,2
    trip_we_1,09:00:00,09:00:00,stop_2,1
    trip_we_1,09:20:00,09:20:00,stop_3,2
    """

    files = [
      {~c"stops.txt", stops},
      {~c"routes.txt", routes},
      {~c"calendar.txt", calendar},
      {~c"trips.txt", trips},
      {~c"stop_times.txt", stop_times}
    ]

    {:ok, {~c"mem.zip", zip_binary}} = :zip.zip(~c"mem.zip", files, [:memory])
    zip_binary
  end

  setup do
    zip_binary = build_mock_gtfs_zip()
    {:ok, g} = GTFSBuilder.from_zip(zip_binary)
    {:ok, zip_binary: zip_binary, graph: g}
  end

  describe "GTFS Ingestion" do
    test "successfully ingests from in-memory zip binary", %{zip_binary: zip_binary} do
      assert {:ok, g} = GTFSBuilder.from_zip(zip_binary)
      assert Graph.node_count(g) == 4
      assert Graph.edge_count(g) == 2

      # Check nodes
      stop1 = Graph.node(g, "stop_1")
      assert stop1.name == "Union Station"
      assert stop1.geometry.coordinates == {-79.3806, 43.6453}
      assert stop1.tags["zone_id"] == "1"

      # Check edges and nested connections
      # stop_1 -> stop_2 has two connections (trip_w_1 and trip_w_2)
      edges = Graph.edges(g)
      edge_1_2 = Enum.find(edges, fn {from, to, _} -> from == "stop_1" and to == "stop_2" end)
      assert {_, _, conns} = edge_1_2
      assert length(conns) == 2

      conn_1 = hd(conns)
      assert conn_1.trip_id == "trip_w_1"
      assert conn_1.departure_time == 8 * 3600
      assert conn_1.arrival_time == 8 * 3600 + 15 * 60

      # stop_2 -> stop_3 has two connections (trip_w_3 and trip_we_1)
      edge_2_3 = Enum.find(edges, fn {from, to, _} -> from == "stop_2" and to == "stop_3" end)
      assert {_, _, conns_2} = edge_2_3
      assert length(conns_2) == 2
    end

    test "respects route_types filter option", %{zip_binary: zip_binary} do
      # Ingest only route_type 1 (subway)
      assert {:ok, g} = GTFSBuilder.from_zip(zip_binary, route_types: [1])
      assert Graph.node_count(g) == 4
      # Only subway trips (trip_w_1, trip_w_2) should yield edges: stop_1 -> stop_2
      assert Graph.edge_count(g) == 1
      edges = Graph.edges(g)
      assert [{"stop_1", "stop_2", _}] = edges
    end

    test "respects service_date filter option (weekday)", %{zip_binary: zip_binary} do
      # May 12, 2026 is a Tuesday (weekday)
      assert {:ok, g} = GTFSBuilder.from_zip(zip_binary, service_date: ~D[2026-05-12])
      assert Graph.node_count(g) == 4
      # Contains weekday trips (trip_w_1, trip_w_2, trip_w_3). trip_we_1 should be excluded.
      edges = Graph.edges(g)
      edge_2_3 = Enum.find(edges, fn {from, to, _} -> from == "stop_2" and to == "stop_3" end)
      assert {_, _, conns} = edge_2_3
      assert length(conns) == 1
      assert hd(conns).trip_id == "trip_w_3"
    end

    test "respects service_date filter option (weekend)", %{zip_binary: zip_binary} do
      # May 10, 2026 is a Sunday (weekend)
      assert {:ok, g} = GTFSBuilder.from_zip(zip_binary, service_date: ~D[2026-05-10])
      assert Graph.node_count(g) == 4
      # Contains only weekend trip (trip_we_1)
      edges = Graph.edges(g)
      # stop_1 -> stop_2 has no active weekday connections
      refute Enum.any?(edges, fn {from, to, _} -> from == "stop_1" and to == "stop_2" end)
      # stop_2 -> stop_3 has trip_we_1
      edge_2_3 = Enum.find(edges, fn {from, to, _} -> from == "stop_2" and to == "stop_3" end)
      assert {_, _, conns} = edge_2_3
      assert length(conns) == 1
      assert hd(conns).trip_id == "trip_we_1"
    end
  end

  describe "GTFS Pathfinding (CSA)" do
    test "finds earliest arrival journey (no transfers needed)", %{graph: g} do
      assert {:ok, journey} =
               Pathfinding.earliest_arrival(g,
                 from: "stop_1",
                 to: "stop_2",
                 departure_time: ~T[07:55:00]
               )

      assert journey.arrival_time == ~T[08:15:00]
      assert length(journey.legs) == 1
      [leg] = journey.legs
      assert leg.from == "stop_1"
      assert leg.to == "stop_2"
      assert leg.trip_id == "trip_w_1"
      assert leg.departure_time == ~T[08:00:00]
      assert leg.arrival_time == ~T[08:15:00]
    end

    test "finds earliest arrival journey with transfers", %{graph: g} do
      # Start at stop_1 at 07:55, take trip_w_1 to stop_2, arrive 08:15.
      # Transfer at stop_2 to trip_w_3 (departs 08:20), arrive at stop_3 at 08:37.
      assert {:ok, journey} =
               Pathfinding.earliest_arrival(g,
                 from: "stop_1",
                 to: "stop_3",
                 departure_time: ~T[07:55:00]
               )

      assert journey.arrival_time == ~T[08:37:00]
      assert length(journey.legs) == 2
      [leg1, leg2] = journey.legs

      assert leg1.from == "stop_1"
      assert leg1.to == "stop_2"
      assert leg1.trip_id == "trip_w_1"

      assert leg2.from == "stop_2"
      assert leg2.to == "stop_3"
      assert leg2.trip_id == "trip_w_3"
    end

    test "respects max_transfers limit", %{graph: g} do
      # Finding path stop_1 -> stop_3 requires 1 transfer (2 trips).
      # If max_transfers: 0, it should fail.
      assert {:error, :no_path} =
               Pathfinding.earliest_arrival(g,
                 from: "stop_1",
                 to: "stop_3",
                 departure_time: ~T[07:55:00],
                 max_transfers: 0
               )
    end

    test "supports walking transfers between nearby stops", %{graph: g} do
      # stop_3 is Kipling, stop_4 is Long Branch Loop
      # Distance between stop_3 and stop_4 is ~5.1 km, too far for 200m walking transfer.
      # Let's verify that a walking transfer occurs when stops are close.
      # We will manually add a closer stop to the graph.
      # ~50 meters from stop_1
      close_point = %Geo.Point{coordinates: {-79.3810, 43.6455}}

      g_modified =
        g
        |> Graph.add_node("stop_close", %{
          geometry: close_point,
          name: "Close Stop",
          gtfs_stop_id: "stop_close"
        })

      # Run earliest_arrival with max_walk_transfer_m: 100
      assert {:ok, journey} =
               Pathfinding.earliest_arrival(g_modified,
                 from: "stop_1",
                 to: "stop_close",
                 departure_time: ~T[08:00:00],
                 max_walk_transfer_m: 100
               )

      assert length(journey.legs) == 1
      [leg] = journey.legs
      assert leg.from == "stop_1"
      assert leg.to == "stop_close"
      assert leg.trip_id == "walk"
    end
  end

  describe "GTFS Queries" do
    test "returns departures after time", %{graph: g} do
      deps = GTFSBuilder.departures_from(g, "stop_1", after: ~T[08:10:00])
      assert length(deps) == 1
      assert hd(deps).trip_id == "trip_w_2"
    end

    test "returns active services for date", %{graph: g} do
      # May 12, 2026 is Tuesday
      services = GTFSBuilder.service_ids_for(g, ~D[2026-05-12])
      assert services == ["service_weekday"]
    end
  end
end
