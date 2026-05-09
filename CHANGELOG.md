# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
