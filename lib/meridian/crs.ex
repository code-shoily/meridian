defmodule Meridian.CRS do
  @moduledoc """
  Coordinate Reference System utilities.

  Meridian defaults to WGS-84 (EPSG:4326). This module provides helpers
  for distance calculations that respect the graph's declared CRS, and
  stubs for reprojection.
  """

  alias Meridian.Graph

  @doc """
  Returns the great-circle distance between two nodes in **meters**.

  Requires that both nodes have `%Geo.Point{}` geometries in their data.
  Currently assumes the graph is in WGS-84.

  Returns `nil` if either node lacks a point geometry.

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {-73.9857, 40.7484}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {-73.9851, 40.7489}}})
      iex> dist = Meridian.CRS.distance(g, :a, :b)
      iex> is_float(dist) and dist > 0
      true

      iex> g = Meridian.Graph.new() |> Meridian.Graph.add_node(:a, %{foo: 1})
      iex> Meridian.CRS.distance(g, :a, :b)
      nil
  """
  @spec distance(Graph.t(), Yog.node_id(), Yog.node_id()) :: float() | nil
  def distance(%Graph{} = graph, from_id, to_id) do
    with %Geo.Point{coordinates: {lon1, lat1}} <- node_point(graph, from_id),
         %Geo.Point{coordinates: {lon2, lat2}} <- node_point(graph, to_id) do
      Geocalc.distance_between([lat1, lon1], [lat2, lon2])
    else
      _ -> nil
    end
  end

  @doc """
  Computes edge weights for all edges as the geographic distance between
  their endpoint nodes.

  Returns a new `Meridian.Graph` where every edge weight has been replaced
  by the computed distance in meters. Edges whose endpoints lack point
  geometries are left unchanged.

  ## Options

    * `:round` — round to N decimal places (default: no rounding)

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})
      ...>   |> Meridian.Graph.add_edge_ensure(:a, :b, nil)
      iex> g = Meridian.CRS.compute_edge_weights(g)
      iex> [{:a, :b, weight}] = Meridian.Graph.edges(g)
      iex> weight > 110_000 and weight < 112_000
      true
  """
  @spec compute_edge_weights(Graph.t(), keyword()) :: Graph.t()
  def compute_edge_weights(%Graph{graph: graph} = mg, opts \\ []) do
    round_to = Keyword.get(opts, :round)
    new_graph = Enum.reduce(Yog.all_edges(graph), graph, &recompute_edge(&2, &1, mg, round_to))
    %{mg | graph: new_graph}
  end

  defp recompute_edge(graph, {from, to, _old}, mg, round_to) do
    case distance(mg, from, to) do
      nil ->
        graph

      dist ->
        weight = if round_to, do: Float.round(dist, round_to), else: dist
        Yog.add_edge_ensure(graph, from, to, weight)
    end
  end

  @doc """
  Reprojects all node geometries to a new CRS.

  > **Note:** Currently a stub. Real reprojection requires a PROJ binding.
  > The CRS field is updated but coordinates are **not** transformed.
  """
  @spec reproject(Graph.t(), String.t()) :: Graph.t()
  def reproject(%Graph{} = g, to_crs) when is_binary(to_crs) do
    # TODO: integrate with proj or rustler NIF for real reprojection
    %{g | crs: to_crs}
  end

  @doc """
  Returns `true` if both graphs declare the same CRS.
  """
  @spec same_crs?(Graph.t(), Graph.t()) :: boolean()
  def same_crs?(%Graph{crs: crs}, %Graph{crs: crs}), do: true
  def same_crs?(_, _), do: false

  @doc """
  Returns the bounding box of a graph as `{min_lon, min_lat, max_lon, max_lat}`.

  Returns `nil` if the graph has no geometries.
  """
  @spec bbox(Graph.t()) :: {float(), float(), float(), float()} | nil
  def bbox(%Graph{bounds: nil}), do: nil

  def bbox(%Graph{bounds: %Geo.Polygon{coordinates: [ring | _]}}) do
    {xs, ys} = Enum.unzip(ring)
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  # --------------------------------------------------------------------------
  # Private
  # --------------------------------------------------------------------------

  defp node_point(%Graph{graph: graph}, id) do
    case Yog.node(graph, id) do
      %{geometry: %Geo.Point{} = p} -> p
      _ -> nil
    end
  end
end
