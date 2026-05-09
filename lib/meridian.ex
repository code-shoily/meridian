defmodule Meridian do
  @moduledoc """
  Meridian brings spatial awareness to `yog_ex` graphs.

  Build projection-aware graphs from hex grids, geohash cells, GeoJSON, or
  OpenStreetMap data. Run spatially-informed algorithms. Render back to maps.

  ## Design

  * `Meridian.Graph` wraps `Yog.Graph` with CRS metadata (`crs`, `srid`, `bounds`).
  * `Meridian.CRS` provides earth-aware distance and reprojection helpers.
  * `Meridian.Geometry` provides pure geometric predicates and measurements.
  * `Meridian.Builder.*` generates spatial graphs from grids or external data.
  * `Meridian.IO.*` ingests geospatial file formats.
  * `Meridian.Render.*` emits geospatial file formats.

  ## Quick Start

      # Hexagonal grid graph (H3)
      graph =
        Meridian.Graph.new(kind: :undirected)
        |> Meridian.Builder.H3.grid(center: {40.7484, -73.9857}, resolution: 9, k_ring: 2)

      # Spatial A* shortest path
      Meridian.Pathfinding.a_star(graph, from: cell_a, to: cell_b)
  """

  @doc """
  Returns the version of Meridian.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:meridian, :vsn)
    |> to_string()
  end
end
