# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Meridian.MultiGraph` — spatial **multigraph** wrapper around `Yog.Multi.Graph` allowing parallel edges between the same node pair. Supports `:first`, `:min_weight`, `:max_weight`, `{:mode, key}`, `{:by, selector}`, and `{:combine, fn}` collapse strategies for converting to a simple `Meridian.Graph`.
- `Meridian.Pathfinding.shortest_path/2` — Dijkstra shortest-path wrapper with the same `:weight_fn` and `:node_filter` options as `a_star/2`.
- `Meridian.Pathfinding.widest_path/2` — maximum bottleneck capacity path wrapper.
- `:weight_fn` now receives edge `data` as a fourth argument (`graph, from, to, data`). Return `nil` or `:infinity` to dynamically exclude edges.
- `:node_filter` option on all pathfinding functions to exclude nodes and all incident edges.
- `Meridian.Spatial` — proximity queries (`within/3`, `nearest/3`) with `:metric` (`:haversine` / `:euclidean`) and `:filter` options.
- `Meridian.Analysis.diameter/2` — exact geographic diameter computed via parallel all-pairs Dijkstra. Returns `%{distance_m, from, to, path}` or `nil` for empty/disconnected graphs. Supports custom `:weight_fn`.
- Full test suite for `Meridian.Analysis` (`test/meridian/analysis_test.exs`) covering diameter edge cases (empty, single-node, disconnected, custom weights, nil/`:infinity` filtering) and `average_edge_length/1`.

## [0.1.0] - 2026-05-09

### Added

- `Meridian.Graph` — spatial graph struct wrapping `Yog.Graph` with `crs`, `srid`, and `bounds` fields.
- `Enumerable` and `Inspect` protocols for `Meridian.Graph`.
- `Meridian.CRS` — haversine distance calculation between nodes, automatic edge-weight computation from geometries, and bounding-box extraction.
- `Meridian.Geometry` — CRS-agnostic helpers: `euclidean/2`, `geo_length/1`, `contains?/2`, `centroid/1`, `envelope/1`.
- `Meridian.Pathfinding` — spatial A* wrapper using haversine distance as the heuristic.
- `Meridian.Builder.H3` — graph generation from Uber H3 hexagonal grids with `:rook` and `:queen` topologies.
- `Meridian.Builder.Geohash` — graph generation from geohash rectangular grids via flood-fill over a bounding box.
- `Meridian.IO.GeoJSON` — GeoJSON ingestion supporting `Point`, `LineString`, `MultiLineString`, `Polygon`, and `FeatureCollection`.
- `Meridian.Render.GeoJSON` — graph rendering to GeoJSON `FeatureCollection` with optional edge emission.
- Optional dependencies: `:h3`, `:geohash`, `:jason`, `:req`. Core compiles without them.
- CRS mismatch detection when merging two `Meridian.Graph` structs.
- 54 tests covering all public modules.
