# Meridian

> Projection-aware spatial graphs for Elixir.

Meridian sits on top of [`yog_ex`](https://hex.pm/packages/yog_ex) and brings
geography into graph theory. Build graphs from maps, run spatial algorithms,
and render your networks back onto the earth.

## Installation

Add `meridian` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:meridian, "~> 0.1.0"}
  ]
end
```

### Optional dependencies

Meridian keeps its core lightweight. Heavy or native dependencies are optional:

| Feature | Dependency | Add to `mix.exs` |
|---------|-----------|------------------|
| H3 hex grids | `:h3` | `{:h3, "~> 3.0"}` |
| Geohash grids | `:geohash` | `{:geohash, "~> 1.3"}` |
| GeoJSON I/O | `:jason` | `{:jason, "~> 1.4"}` |
| HTTP map APIs | `:req` | `{:req, "~> 0.5"}` |

## Quick Start

### H3 hexagonal grid

```elixir
graph =
  Meridian.Graph.new(kind: :undirected)
  |> Meridian.Builder.H3.grid(center: {40.7484, -73.9857}, resolution: 9, k_ring: 2)

Meridian.Graph.node_count(graph)
#=> 19
```

### Geohash grid

```elixir
graph =
  Meridian.Graph.new(kind: :undirected)
  |> Meridian.Builder.Geohash.grid(
       sw: {40.6, -74.1},
       ne: {40.8, -73.9},
       precision: 5,
       topology: :rook
     )
```

### GeoJSON ingest

```elixir
{:ok, graph} =
  "roads.geojson"
  |> File.read!()
  |> Meridian.IO.GeoJSON.from_string()
```

### Spatial shortest path

```elixir
{:ok, path} =
  Meridian.Pathfinding.a_star(graph, from: :a, to: :b)

path.nodes
#=> [:a, :intersection_3, :b]
path.total_weight
#=> 1240.5
```

### Render back to GeoJSON

```elixir
graph
|> Meridian.Render.GeoJSON.to_string()
|> File.write!("output.geojson")
```

## Architecture

Meridian wraps `Yog.Graph` in a `Meridian.Graph` struct that carries spatial
metadata:

```elixir
%Meridian.Graph{
  graph: %Yog.Graph{},
  crs: "EPSG:4326",
  srid: 4326,
  bounds: %Geo.Polygon{}
}
```

This means every coordinate in the graph lives in a known, declared coordinate
reference system. Merging two graphs with different CRS values raises an
`ArgumentError` — no silent coordinate confusion.

## Modules

| Module | Purpose |
|--------|---------|
| `Meridian.Graph` | Spatial graph struct, queries, and modifications |
| `Meridian.CRS` | Earth-aware distances, edge-weight computation, bounding boxes |
| `Meridian.Geometry` | CRS-agnostic geometric helpers (euclidean, centroid, contains?) |
| `Meridian.Pathfinding` | Spatially-informed A* with haversine heuristics |
| `Meridian.Builder.H3` | Hexagonal grid graphs via Uber H3 |
| `Meridian.Builder.Geohash` | Rectangular grid graphs via geohash |
| `Meridian.IO.GeoJSON` | GeoJSON → graph ingestion |
| `Meridian.Render.GeoJSON` | Graph → GeoJSON rendering |

## Protocols

`Meridian.Graph` implements `Enumerable` and `Inspect`:

```elixir
graph = Meridian.Graph.new() |> Meridian.Graph.add_node(1, %{name: "A"})
Enum.to_list(graph)
#=> [{1, %{name: "A"}}]

inspect(graph)
#=> "#Meridian.Graph<EPSG:4326, 1 node, 0 edges>"
```

## Relationship to `yog_ex`

`yog_ex` provides the graph engine: Dijkstra, A*, Bellman-Ford, community
detection, connectivity, and every other graph algorithm you might need.
Meridian adds the *spatial layer* on top: coordinate systems, map ingestion,
grid builders, and geographic heuristics.

You can drop down to raw `yog_ex` at any time:

```elixir
yog = Meridian.Graph.to_yog(graph)
Yog.Pathfinding.Dijkstra.shortest_path(yog, from: :a, to: :b)
```

## Roadmap

- [ ] OSM Overpass / PBF ingestion
- [ ] Network buffers and reachable-area queries
- [ ] Spatial indexing (R-tree or H3-based)
- [ ] Real CRS reprojection (PROJ / Rustler)
- [ ] Kino / Livebook map rendering
- [ ] MVT (Mapbox Vector Tile) encoding

## License

MIT License — see [LICENSE](./LICENSE) for details.
