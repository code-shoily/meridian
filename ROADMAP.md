# Roadmap

This is a living document. Checked items ship with the tagged version; unchecked items are up for grabs.

## Core Infrastructure

- [x] `Meridian.Graph` — spatial graph struct with CRS, SRID, bounds
- [x] `Enumerable` and `Inspect` protocols
- [x] `Meridian.CRS` — haversine distances, edge-weight computation, bounding boxes
- [x] `Meridian.Geometry` — euclidean, centroid, envelope, contains?, geo_length
- [ ] Real CRS reprojection (PROJ / Rustler NIF)
- [ ] Spatial indexing — R-tree or H3-based spatial lookup for fast `within` / `nearest` queries
- [ ] Network buffers — nodes reachable within N meters of *graph* distance (not crow-flies)

## Builders

- [x] `Meridian.Builder.H3` — hexagonal grids
- [x] `Meridian.Builder.Geohash` — rectangular grids
- [ ] `Meridian.Builder.OSM` — OpenStreetMap Overpass / PBF ingestion
- [ ] `Meridian.Builder.Delaunay` — Delaunay triangulation from point clouds
- [ ] `Meridian.Builder.Gabriel` — Gabriel graph from point sets
- [ ] `Meridian.Builder.Grid` — generic coordinate grid (non-geographic metric space)
- [ ] H3 `:queen` topology with true vertex adjacency via unidirectional edges

## I/O

- [x] GeoJSON ingest (`Meridian.IO.GeoJSON`)
- [x] GeoJSON render (`Meridian.Render.GeoJSON`)
- [ ] OSM XML / PBF parser
- [ ] Shapefile ingest (via `ogr2ogr` or pure-Elixir parser)
- [ ] GTFS ingest (transit networks)
- [ ] MVT (Mapbox Vector Tile) encoding

## Pathfinding & Analysis

- [x] A* with haversine heuristic
- [x] Dijkstra shortest path (`shortest_path/2`)
- [x] Widest path / maximum bottleneck (`widest_path/2`)
- [x] Dynamic edge filtering via `:infinity` / `nil` weights
- [x] Dynamic node filtering via `:node_filter`
- [ ] `Meridian.Pathfinding.yen` — k-shortest paths with spatial pruning
- [x] `Meridian.Spatial.within/3` — all nodes within radius
- [x] `Meridian.Spatial.nearest/3` — nearest N nodes by crow-flies
- [ ] `Meridian.Spatial.nearest_reachable/3` — nearest node satisfying predicate via road network
- [ ] `Meridian.Analysis.alpha_shape` — concave hull of graph nodes
- [ ] `Meridian.Analysis.connected_components_by_distance` — components within threshold

## Visualization

- [x] `Meridian.Render.MapLibre` — Livebook map renderer via MapLibre
- [ ] Choropleth / heatmap layer generation from graph metrics
- [ ] Animated path playback on map

## Performance

- [ ] Benchmark suite comparing spatial A* vs pure Dijkstra
- [ ] Streaming OSM ingestion (process planet files without loading into memory)
- [ ] Parallel graph construction for large grids

## Experimental

- [x] `Meridian.MultiGraph` — multigraph wrapper around `Yog.Multi.Graph` (may change or be removed)

## Docs & Tooling

- [x] Doctests enabled
- [x] Credo clean
- [x] Dialyzer clean
- [x] ExCoveralls with 80% minimum threshold
- [x] Livebook getting-started guide
- [ ] Livebook guides — "Building a street network from OSM", "H3-based delivery zones"
- [ ] HexDocs with embedded map widgets
