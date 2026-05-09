# Design Doc: `Meridian.Builder.GTFS` — Transit Network Ingestion

**Status:** Draft  
**Author:** @code-shoily  
**Date:** 2026-05-09  
**Priority:** High  
**Target Release:** v0.2.0  

---

## 1. Problem Statement

GTFS (General Transit Feed Specification) is the de-facto standard for public transit data. A GTFS feed is a collection of CSV files describing stops, routes, trips, and schedules. Meridian should be able to ingest a GTFS feed and produce a spatial graph where:

- **Nodes** = transit stops with real-world coordinates
- **Edges** = trip segments with scheduled departure/arrival times

This unlocks **timetable-based routing** — finding the earliest arrival from stop A to stop B given a departure time and date.

## 2. Why This Is the Next Natural Step

1. **Spatial + temporal** — GTFS is a perfect bridge between Meridian's spatial graph foundation and real-world routing.
2. **Builds on pathfinding** — The `node_filter` / `weight_fn` work we just shipped is exactly the mechanism needed for service-day filtering and transfer penalties.
3. **Complements OSM** — OSM gives you the street network; GTFS gives you the transit layer. Together they enable true multi-modal routing (walk to bus, ride bus, walk to destination).

## 3. GTFS Data Model (Simplified)

| File | What It Describes | Maps To |
|---|---|---|
| `stops.txt` | Stop locations (lat, lon, name) | Graph nodes |
| `routes.txt` | Route metadata (name, type, color) | Edge properties |
| `trips.txt` | Individual journeys on a route | Trip identifiers |
| `stop_times.txt` | Arrival/departure at each stop per trip | Edge time data |
| `calendar.txt` | Which days a service runs | Service filter |
| `shapes.txt` | Route geometries (optional) | Edge geometry |

## 4. Graph Construction

### 4.1 Nodes (Stops)

```elixir
%{
  geometry: %Geo.Point{coordinates: {-79.3806, 43.6453}},
  name: "Union Station",
  gtfs_stop_id: "union",
  wheelchair_boarding: 1,
  tags: %{"zone_id" => "1"}
}
```

### 4.2 Edges (Trip Segments)

A GTFS trip is a sequence of stop visits. Each consecutive pair becomes an edge:

```
Trip T1:  S1 --[08:00→08:05]--> S2 --[08:07→08:12]--> S3
Edges:   (S1,S2, dep:08:00, arr:08:05, trip:T1)
         (S2,S3, dep:08:07, arr:08:12, trip:T1)
```

Edge data:

```elixir
%{
  trip_id: "T1",
  route_id: "R1",
  service_id: "WEEKDAY",
  departure_time: ~T[08:00:00],
  arrival_time: ~T[08:05:00],
  stop_sequence: 1,
  headsign: "Downtown",
  shape_dist_traveled: 1200.0  # meters from start of trip
}
```

> **Note on time representation:** GTFS uses `HH:MM:SS` strings that can exceed 24 hours (e.g., `25:30:00` for 1:30 AM next day). We parse these as elapsed seconds since noon-minus-12h of the service day.

### 4.3 The Transfer Problem

A rider can:
1. **Ride** a trip from stop A to stop B (follow an edge)
2. **Wait** at a stop for the next trip
3. **Transfer** between trips at the same stop (or nearby stops)

This means a simple static-weight graph is insufficient. The graph structure is static (stops and trip segments), but the **routing is time-dependent**.

## 5. Routing Algorithm: Connection-Scan (CSA)

For timetable routing, the [Connection-Scan Algorithm](https://en.wikipedia.org/wiki/Connection_scan_algorithm) is the gold standard:

1. **Pre-sort** all connections (edges) by departure time
2. **Initialize** earliest arrival at origin = departure time; all others = ∞
3. **Scan** connections in departure-time order:
   - If the connection departs from a stop we can already reach by its departure time,
   - Then we can reach its arrival stop at the connection's arrival time
4. **Handle transfers** — after scanning, apply transfer rules at each reached stop

**Time complexity:** O(|C|) where C = number of connections. Very fast.

**Meridian API:**

```elixir
{:ok, journey} = Meridian.Pathfinding.earliest_arrival(graph,
  from: "stop_127",
  to: "stop_456",
  departure_time: ~T[08:00:00],
  date: ~D[2026-05-12]
)

journey.arrival_time   # => ~T[08:37:00]
journey.legs           # => [
                       #      %{from: "union", to: "spadina",
                       #        trip: "T42", dep: ~T[08:00:00], arr: ~T[08:15:00]},
                       #      %{from: "spadina", to: "kipling",
                       #        trip: "T88", dep: ~T[08:20:00], arr: ~T[08:37:00]}
                       #    ]
```

## 6. Proposed API

### 6.1 Ingestion

```elixir
# From a GTFS zip file
{:ok, graph} = Meridian.Builder.GTFS.from_zip("ttc_gtfs.zip")

# From a directory of extracted .txt files
{:ok, graph} = Meridian.Builder.GTFS.from_dir("/path/to/gtfs/")

# With options
{:ok, graph} = Meridian.Builder.GTFS.from_zip("gtfs.zip",
  route_types: [0, 1],        # only subway and light rail
  service_date: ~D[2026-05-12] # only include trips running this day
)
```

### 6.2 Routing

```elixir
# Earliest arrival
{:ok, journey} = Meridian.Pathfinding.earliest_arrival(graph,
  from: "union",
  to: "kipling",
  departure_time: ~T[08:00:00],
  date: ~D[2026-05-12]
)

# With max transfers
{:ok, journey} = Meridian.Pathfinding.earliest_arrival(graph,
  from: "union",
  to: "kipling",
  departure_time: ~T[08:00:00],
  date: ~D[2026-05-12],
  max_transfers: 2
)

# With walking transfer between nearby stops
{:ok, journey} = Meridian.Pathfinding.earliest_arrival(graph,
  from: "union",
  to: "kipling",
  departure_time: ~T[08:00:00],
  date: ~D[2026-05-12],
  walk_speed_mps: 1.4,           # 1.4 m/s ≈ 5 km/h
  max_walk_transfer_m: 200       # allow 200m walk transfers
)
```

### 6.3 Querying

```elixir
# All trips departing from a stop after a given time
Meridian.Builder.GTFS.departures_from(graph, "union", after: ~T[08:00:00])

# Service calendar for a date
Meridian.Builder.GTFS.service_ids_for(graph, ~D[2026-05-12])
```

## 7. Dependencies

| Dependency | Purpose | Optional? |
|---|---|---|
| `:nimble_csv` | Parse GTFS CSV files | No (lightweight) |
| `:req` | Download GTFS feeds from URLs | Yes (already optional) |
| `:jason` | Parse GTFS-Realtime (future) | Yes (already optional) |

No new heavy dependencies required.

## 8. Scope

### v0.2.0 (MVP)
- [ ] Parse `stops.txt`, `routes.txt`, `trips.txt`, `stop_times.txt`, `calendar.txt`
- [ ] Build `Meridian.Graph` with stops as nodes, trip segments as edges
- [ ] Connection-Scan Algorithm for earliest arrival
- [ ] Service-day filtering (only include trips running on a given date)
- [ ] Tests with a small real GTFS feed (e.g., a single bus line)

### v0.3.0 (Enhanced)
- [ ] `shapes.txt` ingestion for edge geometries
- [ ] `transfers.txt` support (explicit transfer rules)
- [ ] `frequencies.txt` support (headway-based rather than exact times)
- [ ] GTFS-Realtime integration (live delays)
- [ ] Multi-criteria routing (earliest arrival vs fewest transfers vs least walking)

### Future
- [ ] Multi-modal routing combining GTFS + OSM street network
- [ ] Isochrone generation (all reachable stops within N minutes)
- [ ] RAPTOR algorithm for profile queries (all Pareto-optimal journeys)

## 9. Testing Strategy

- **Unit tests:** Parse fixtures for each GTFS file type
- **Integration tests:** Use a small real GTFS feed (e.g., a city's bus data, ~5 stops, ~3 trips)
- **Doctests:** Realistic earliest-arrival example
- **Property tests:** Round-trip — build graph → query → verify arrival times match source data

## 10. Open Questions

1. Should we store **all** trip segments as edges (can be millions for large feeds), or provide a lazy/streaming builder?
2. How should we handle **GTFS time values > 24:00:00**? Parse as elapsed seconds, or keep as strings?
3. Should `earliest_arrival/2` return a **single** best journey, or a **profile** of options (earliest vs fewest transfers)?
4. Should we support **GTFS-Realtime** as a dynamic `node_filter` / `weight_fn` layer on top of the static graph?
5. How do we handle **transfers** without `transfers.txt`? Auto-generate based on walk distance between stops?
