defmodule Meridian.Geometry do
  @moduledoc """
  Pure-geometric helpers operating on `Geo` structs and `Yog.Graph` nodes.

  These functions are CRS-agnostic: they work with whatever coordinates you
  give them. When you need earth-aware distances, use `Meridian.CRS`.
  """

  @doc """
  Computes the bounding envelope of all node geometries in a graph.

  Returns a `%Geo.Polygon{}` representing the bounding box, or `nil` if
  no geometries are present.

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g
      ...>   |> Meridian.Graph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      ...>   |> Meridian.Graph.add_node(:b, %{geometry: %Geo.Point{coordinates: {2.0, 3.0}}})
      iex> %Geo.Polygon{} = Meridian.Geometry.envelope(Meridian.Graph.to_yog(g))
  """
  @spec envelope(Yog.Graph.t()) :: Geo.Polygon.t() | nil
  def envelope(%Yog.Graph{nodes: nodes}) when map_size(nodes) == 0, do: nil

  def envelope(%Yog.Graph{nodes: nodes}) do
    coords =
      Enum.flat_map(nodes, fn
        {_id, %{geometry: %Geo.Point{coordinates: {x, y}}}} -> [{x, y}]
        {_id, %{geometry: %Geo.Polygon{coordinates: rings}}} -> List.flatten(rings)
        {_id, %{geometry: %Geo.LineString{coordinates: cs}}} -> cs
        _ -> []
      end)

    case coords do
      [] ->
        nil

      _ ->
        {xs, ys} = Enum.unzip(coords)
        min_x = Enum.min(xs)
        max_x = Enum.max(xs)
        min_y = Enum.min(ys)
        max_y = Enum.max(ys)

        %Geo.Polygon{
          coordinates: [
            [
              {min_x, min_y},
              {max_x, min_y},
              {max_x, max_y},
              {min_x, max_y},
              {min_x, min_y}
            ]
          ]
        }
    end
  end

  @doc """
  Euclidean distance between two points.

  ## Examples

      iex> a = %Geo.Point{coordinates: {0.0, 0.0}}
      iex> b = %Geo.Point{coordinates: {3.0, 4.0}}
      iex> Meridian.Geometry.euclidean(a, b)
      5.0
  """
  @spec euclidean(Geo.Point.t(), Geo.Point.t()) :: float()
  def euclidean(%Geo.Point{coordinates: {x1, y1}}, %Geo.Point{coordinates: {x2, y2}}) do
    :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))
  end

  @doc """
  Approximate length of a `Geo.LineString` in meters using the haversine formula.

  Sums the great-circle distance of each segment.

  ## Examples

      iex> line = %Geo.LineString{coordinates: [{0.0, 0.0}, {0.0, 1.0}]}
      iex> len = Meridian.Geometry.geo_length(line)
      iex> len > 110_000 and len < 112_000
      true
  """
  @spec geo_length(Geo.LineString.t()) :: float()
  def geo_length(%Geo.LineString{coordinates: coords}) when length(coords) < 2, do: 0.0

  def geo_length(%Geo.LineString{coordinates: coords}) do
    coords
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [{lon1, lat1}, {lon2, lat2}], acc ->
      acc + Geocalc.distance_between([lat1, lon1], [lat2, lon2])
    end)
  end

  @doc """
  Returns true if `point` lies inside `polygon`.

  Uses a simple ray-casting algorithm. Works for simple polygons.

  ## Examples

      iex> poly = %Geo.Polygon{coordinates: [[{0,0},{10,0},{10,10},{0,10},{0,0}]]}
      iex> Meridian.Geometry.contains?(poly, %Geo.Point{coordinates: {5, 5}})
      true
      iex> Meridian.Geometry.contains?(poly, %Geo.Point{coordinates: {15, 5}})
      false
  """
  @spec contains?(Geo.Polygon.t(), Geo.Point.t()) :: boolean()
  def contains?(%Geo.Polygon{coordinates: [ring | _]}, %Geo.Point{coordinates: {px, py}}) do
    ring
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(false, fn [{x1, y1}, {x2, y2}], inside ->
      if y1 > py != y2 > py and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1 do
        not inside
      else
        inside
      end
    end)
  end

  @doc """
  Computes the centroid of a `Geo.Polygon` as a `Geo.Point`.

  Uses the arithmetic mean of vertices (not area-weighted).

  ## Examples

      iex> poly = %Geo.Polygon{coordinates: [[{0,0},{10,0},{10,10},{0,10},{0,0}]]}
      iex> centroid = Meridian.Geometry.centroid(poly)
      iex> centroid.coordinates
      {5.0, 5.0}
  """
  @spec centroid(Geo.Polygon.t()) :: Geo.Point.t()
  def centroid(%Geo.Polygon{coordinates: [ring | _]}) do
    # Drop the closing vertex (last point repeats first)
    points = Enum.drop(ring, -1)
    {xs, ys} = Enum.unzip(points)
    count = length(xs)

    %Geo.Point{
      coordinates: {Enum.sum(xs) / count, Enum.sum(ys) / count}
    }
  end
end
