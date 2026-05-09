# Design Doc: `Meridian.Builder.OSM`

**Status:** Draft  
**Author:** @code-shoily  
**Date:** 2026-05-09  
**Target Release:** v0.2.0

---

## 1. Problem Statement

Meridian needs a way to ingest real-world street networks from OpenStreetMap (OSM). Currently users must manually create graphs node-by-node. An OSM builder would let users go from a bounding box or a `.osm.pbf` file to a routable `Meridian.Graph` in one call.

## 2. Goals

- Convert an OSM bounding-box query (via Overpass API) into a `Meridian.Graph`
- Preserve OSM tags on nodes and edges for downstream filtering / weighting
- Handle one-way streets correctly
- Split OSM "ways" at intersections to create a true road-network graph
- Compute edge weights from node geometries

## 3. Non-Goals

- Parsing `.osm.pbf` files (v0.2.0 scope is Overpass only)
- Turn restrictions (relations)
- Elevation-aware routing
- Real-time traffic data
- Routing profiles (car vs bike vs walk) — these are user-level `weight_fn` concerns

## 4. API Design

### 4.1 Overpass (Primary)

```elixir
Meridian.Builder.OSM.from_bbox(
  sw: {lat, lon},          # required: south-west corner
  ne: {lat, lon},          # required: north-east corner
  highway: [...],          # optional: list of highway types (default: common drivable)
  oneway_as_directed: true # optional: create directed edges for oneways (default: true)
)
```

**Example:**

```elixir
graph =
  Meridian.Builder.OSM.from_bbox(
    sw: {43.6426, -79.3871},
    ne: {43.6487, -79.3753},
    highway: ["primary", "secondary", "tertiary", "residential"]
  )

Graph.node_count(graph)  # => ~500
Graph.edge_count(graph)  # => ~1200
```

### 4.2 From Raw Overpass JSON

For users who already have Overpass data:

```elixir
{:ok, graph} = Meridian.Builder.OSM.from_overpass_json(json_string)
```

### 4.3 PBF (Future)

```elixir
# NOT in v0.2.0
Meridian.Builder.OSM.from_pbf("toronto.osm.pbf", highway: [...])
```

## 5. Data Model

### 5.1 Node Data

```elixir
%{
  geometry: %Geo.Point{coordinates: {lon, lat}},
  osm_id: 123_456,
  tags: %{"highway" => "traffic_signals"}
}
```

### 5.2 Edge Data

```elixir
%{
  osm_way_id: 789_012,
  name: "Bay St",
  highway: "primary",
  oneway: true,           # inferred from OSM tag
  maxspeed: 40,           # parsed from tag when present
  distance_m: 150.5,      # haversine from node geometries
  lanes: 4,               # parsed from tag when present
  surface: "asphalt",     # parsed from tag when present
  tags: %{...}            # all remaining OSM tags
}
```

## 6. Algorithm

### 6.1 Overpass Query

Use the Overpass API `[out:json]` format. Query for:
- All `node`s inside the bbox
- All `way`s that reference those nodes AND have a `highway` tag in the allowed list

```overpass
[out:json];
way["highway"~"^(primary|secondary|tertiary|residential)$"]({{sw_lat}},{{sw_lon}},{{ne_lat}},{{ne_lon}});
(._;>;);
out body;
```

### 6.2 Graph Construction Pipeline

```
Overpass Response
    │
    ▼
┌─────────────────┐
│ 1. Index Nodes  │  →  %{osm_node_id => %Geo.Point{}}
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 2. Index Ways   │  →  %{osm_way_id => [node_id, node_id, ...]}
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 3. Find X nodes │  →  node_ids that appear in ≥2 ways
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 4. Split Ways   │  →  [{from_id, to_id, way_data}, ...]
│    at X nodes   │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ 5. Build Graph  │  →  Meridian.Graph with computed weights
└─────────────────┘
```

### 6.3 Intersection Detection

A node is an intersection if it appears in the node-ref list of ≥2 ways, OR it is the first/last node of a way (dead-end or terminus).

```elixir
node_way_counts =
  ways
  |> Enum.flat_map(fn {_way_id, node_refs} -> node_refs end)
  |> Enum.frequencies()

intersection? = fn node_id ->
  Map.get(node_way_counts, node_id, 0) >= 2
end
```

### 6.4 Way Splitting

For each way's node-ref list, iterate and emit an edge segment every time you hit an intersection node:

```
Way nodes: [A, B, C, D, E]
Intersections: A, C, E

Segments: [A→B→C], [C→D→E]
```

Each segment becomes one graph edge. The segment's geometry is derived from its start and end nodes (not intermediate nodes, to keep the graph simple).

> **Open question:** Should we store the full polyline as edge data for visualization?

### 6.5 One-Way Handling

If `oneway_as_directed: true` (default):
- `oneway=yes` → directed edge only
- `oneway=-1` → directed edge reversed
- `oneway=no` or absent → undirected edge (or bidirectional directed edges)

If `oneway_as_directed: false`, all edges are undirected regardless of tags.

## 7. Error Handling

| Scenario | Behavior |
|---|---|
| Overpass rate limit | Return `{:error, "Overpass rate limit"}` |
| Empty bbox (no roads) | Return `{:ok, empty_graph}` |
| Invalid bbox (sw > ne) | Raise `ArgumentError` |
| `req` not available | Raise `ArgumentError` at runtime |
| Network timeout | Return `{:error, reason}` |

## 8. Dependencies

- `:req` (already optional) — for Overpass HTTP calls
- `:jason` (already optional) — for JSON parsing

No new dependencies for v0.2.0.

## 9. Testing Strategy

- **Unit tests:** Mock Overpass response with fixtures
- **Integration tests:** Small real bbox query (e.g., a city block)
- **Doctests:** Realistic example with a well-known intersection

## 10. Future Work

- `.osm.pbf` ingestion via `pbf_parser`
- Turn restrictions (OSM relations)
- Elevation profiles via SRTM / DEM
- Live traffic integration
- Routing profiles (built-in `weight_fn` presets)

## 11. Open Questions

1. Should intermediate way nodes (between intersections) be dropped from the graph, or stored as edge geometry?
2. Should we cache Overpass responses to disk to avoid re-querying?
3. How should we handle very large bboxes (thousands of nodes)? Stream the response?
4. Should `highway` default to a sensible list, or require explicit opt-in?
