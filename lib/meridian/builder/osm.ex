defmodule Meridian.Builder.OSM do
  @moduledoc """
  Builds graphs from OpenStreetMap (OSM) data.

  Requires the optional `:req` and `:jason` dependencies.

  This builder converts OSM bounding-box queries (via the Overpass API)
  or raw Overpass JSON responses into a `Meridian.Graph`.
  """

  alias Meridian.Graph

  @doc """
  Queries the Overpass API for roads within a bounding box and constructs a `Meridian.Graph`.

  ## Options

    * `:sw` — south-west corner `{lat, lon}` (required)
    * `:ne` — north-east corner `{lat, lon}` (required)
    * `:highway` — list of highway types to include (default: `["primary", "secondary", "tertiary", "residential"]`)
    * `:oneway_as_directed` — if `true`, creates directed edges for oneway roads (default: `true`)
    * `:kind` — graph kind: `:directed` (default) or `:undirected`

  ## Examples

      # Typically called via:
      # {:ok, graph} = Meridian.Builder.OSM.from_bbox(
      #   sw: {43.6426, -79.3871},
      #   ne: {43.6487, -79.3753}
      # )
  """
  @spec from_bbox(keyword()) :: {:ok, Graph.t()} | {:error, term()}
  def from_bbox(opts) do
    unless Code.ensure_loaded?(Req) do
      raise RuntimeError,
            "Meridian.Builder.OSM requires the :req dependency. Add `{:req, \"~> 0.5\"}` to your deps."
    end

    sw = Keyword.fetch!(opts, :sw)
    ne = Keyword.fetch!(opts, :ne)

    validate_bbox!(sw, ne)

    {sw_lat, sw_lon} = sw
    {ne_lat, ne_lon} = ne

    highway_types =
      Keyword.get(opts, :highway, ["primary", "secondary", "tertiary", "residential"])

    highway_regex = "^(" <> Enum.join(highway_types, "|") <> ")$"

    query = """
    [out:json];
    way["highway"~"#{highway_regex}"](#{sw_lat},#{sw_lon},#{ne_lat},#{ne_lon});
    (._;>;);
    out body;
    """

    url = "https://overpass-api.de/api/interpreter"

    case Req.post(url, form: [data: query]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        from_overpass_json(body, opts)

      {:ok, %Req.Response{status: 429}} ->
        {:error, "Overpass rate limit"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Overpass query failed with status #{status}"}

      {:error, %{reason: reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Constructs a `Meridian.Graph` from a raw Overpass JSON response.

  Accepts either a JSON binary string or a pre-parsed map.
  """
  @spec from_overpass_json(String.t() | map(), keyword()) :: {:ok, Graph.t()} | {:error, term()}
  def from_overpass_json(json, opts \\ []) do
    parsed_json =
      if is_binary(json) do
        unless Code.ensure_loaded?(Jason) do
          raise RuntimeError,
                "Meridian.Builder.OSM requires the :jason dependency. Add `{:jason, \"~> 1.4\"}` to your deps."
        end

        case Jason.decode(json) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_error, reason}}
        end
      else
        {:ok, json}
      end

    case parsed_json do
      {:ok, %{"elements" => elements}} ->
        build_graph_from_elements(elements, opts)

      {:ok, _} ->
        {:error, "Invalid Overpass JSON response format"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --------------------------------------------------------------------------
  # Private functions
  # --------------------------------------------------------------------------

  defp validate_bbox!({sw_lat, sw_lon}, {ne_lat, ne_lon}) do
    if sw_lat >= ne_lat or sw_lon >= ne_lon do
      raise ArgumentError, "invalid bbox: southwest corner must be less than northeast corner"
    end
  end

  defp build_graph_from_elements(elements, opts) do
    kind = Keyword.get(opts, :kind, :directed)
    oneway_as_directed = Keyword.get(opts, :oneway_as_directed, true)

    highway_types =
      Keyword.get(opts, :highway, ["primary", "secondary", "tertiary", "residential"])

    nodes_map = index_nodes(elements)
    ways = index_ways(elements, nodes_map, highway_types)
    intersection_ids = find_intersections(ways)
    segments = build_segments(ways, intersection_ids, nodes_map)

    Graph.new(kind: kind)
    |> add_nodes_to_graph(segments, nodes_map)
    |> add_edges_to_graph(segments, oneway_as_directed)
    |> Graph.recompute_bounds()
    |> then(&{:ok, &1})
  end

  defp index_nodes(elements) do
    elements
    |> Stream.filter(fn elem -> elem["type"] == "node" end)
    |> Stream.map(fn elem ->
      id = elem["id"]
      lat = elem["lat"]
      lon = elem["lon"]
      tags = elem["tags"] || %{}
      {id, %{id: id, lat: lat, lon: lon, tags: tags}}
    end)
    |> Map.new()
  end

  defp index_ways(elements, nodes_map, highway_types) do
    elements
    |> Stream.filter(fn elem ->
      elem["type"] == "way" and is_list(elem["nodes"]) and is_map(elem["tags"])
    end)
    |> Stream.filter(fn elem ->
      highway = Map.get(elem["tags"], "highway")
      is_binary(highway) and highway in highway_types
    end)
    |> Enum.map(fn elem ->
      %{
        id: elem["id"],
        nodes: Enum.filter(elem["nodes"], &Map.has_key?(nodes_map, &1)),
        tags: elem["tags"]
      }
    end)
  end

  defp find_intersections(ways) do
    node_frequencies =
      ways
      |> Stream.flat_map(fn way -> way.nodes end)
      |> Enum.frequencies()

    endpoints =
      Enum.reduce(ways, MapSet.new(), fn way, acc ->
        add_way_endpoints(acc, way.nodes)
      end)

    Enum.reduce(node_frequencies, endpoints, fn {node_id, freq}, acc ->
      add_frequent_node(acc, node_id, freq)
    end)
  end

  defp add_frequent_node(acc, node_id, freq) when freq >= 2, do: MapSet.put(acc, node_id)
  defp add_frequent_node(acc, _node_id, _freq), do: acc

  defp add_way_endpoints(acc, []), do: acc
  defp add_way_endpoints(acc, [single]), do: MapSet.put(acc, single)

  defp add_way_endpoints(acc, [first | _] = nodes) do
    last = List.last(nodes)
    acc |> MapSet.put(first) |> MapSet.put(last)
  end

  defp build_segments(ways, intersection_ids, nodes_map) do
    ways
    |> Enum.flat_map(fn way ->
      way.nodes
      |> split_into_segments(intersection_ids)
      |> Enum.map(&build_segment_edge(&1, nodes_map, way))
    end)
  end

  defp build_segment_edge(segment, nodes_map, way) do
    start_id = hd(segment)
    end_id = List.last(segment)
    distance = compute_segment_distance(segment, nodes_map)

    oneway_val = Map.get(way.tags, "oneway")
    junction_val = Map.get(way.tags, "junction")

    direction = parse_direction(oneway_val, junction_val)

    edge_data = %{
      osm_way_id: way.id,
      name: Map.get(way.tags, "name"),
      highway: Map.get(way.tags, "highway"),
      oneway: oneway_val in ["yes", "true", "1", "-1"] or junction_val == "roundabout",
      maxspeed: parse_maxspeed(Map.get(way.tags, "maxspeed")),
      distance_m: distance,
      lanes: parse_lanes(Map.get(way.tags, "lanes")),
      surface: Map.get(way.tags, "surface"),
      tags: way.tags
    }

    {start_id, end_id, direction, edge_data}
  end

  defp parse_direction(oneway_val, _junction) when oneway_val in ["yes", "true", "1"],
    do: :forward

  defp parse_direction("-1", _junction), do: :reverse
  defp parse_direction(_oneway, "roundabout"), do: :forward
  defp parse_direction(_oneway, _junction), do: :bidirectional

  defp add_nodes_to_graph(graph, segments, nodes_map) do
    active_node_ids =
      Enum.reduce(segments, MapSet.new(), fn {start_id, end_id, _dir, _data}, acc ->
        acc |> MapSet.put(start_id) |> MapSet.put(end_id)
      end)

    Enum.reduce(active_node_ids, graph, fn node_id, acc ->
      %{lat: lat, lon: lon, tags: tags} = Map.fetch!(nodes_map, node_id)

      node_data = %{
        geometry: %Geo.Point{coordinates: {lon, lat}},
        osm_id: node_id,
        tags: tags
      }

      Graph.add_node(acc, node_id, node_data)
    end)
  end

  defp add_edges_to_graph(graph, segments, oneway_as_directed) do
    Enum.reduce(segments, graph, fn {start_id, end_id, direction, edge_data}, acc ->
      add_segment_edge(acc, start_id, end_id, direction, edge_data, oneway_as_directed)
    end)
  end

  defp add_segment_edge(graph, start_id, end_id, direction, edge_data, oneway_as_directed) do
    if Graph.kind(graph) == :undirected do
      Graph.add_edge_ensure(graph, start_id, end_id, edge_data)
    else
      add_directed_edge(graph, start_id, end_id, direction, edge_data, oneway_as_directed)
    end
  end

  defp add_directed_edge(graph, start_id, end_id, direction, edge_data, true) do
    case direction do
      :forward ->
        Graph.add_edge_ensure(graph, start_id, end_id, edge_data)

      :reverse ->
        Graph.add_edge_ensure(graph, end_id, start_id, edge_data)

      :bidirectional ->
        graph
        |> Graph.add_edge_ensure(start_id, end_id, edge_data)
        |> Graph.add_edge_ensure(end_id, start_id, edge_data)
    end
  end

  defp add_directed_edge(graph, start_id, end_id, _direction, edge_data, false) do
    graph
    |> Graph.add_edge_ensure(start_id, end_id, edge_data)
    |> Graph.add_edge_ensure(end_id, start_id, edge_data)
  end

  defp split_into_segments(nodes, intersection_ids) do
    split_into_segments(nodes, intersection_ids, [], [])
  end

  defp split_into_segments([], _intersections, _curr, acc), do: Enum.reverse(acc)

  defp split_into_segments([h | t], intersections, [], acc) do
    split_into_segments(t, intersections, [h], acc)
  end

  defp split_into_segments([h | t], intersections, curr, acc) do
    new_curr = [h | curr]

    if MapSet.member?(intersections, h) do
      segment = Enum.reverse(new_curr)
      # If segment has at least 2 nodes, accumulate it
      new_acc = if length(segment) >= 2, do: [segment | acc], else: acc
      split_into_segments(t, intersections, [h], new_acc)
    else
      split_into_segments(t, intersections, new_curr, acc)
    end
  end

  defp compute_segment_distance(segment, nodes_map) do
    segment
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [id1, id2], acc ->
      case {Map.get(nodes_map, id1), Map.get(nodes_map, id2)} do
        {%{lat: lat1, lon: lon1}, %{lat: lat2, lon: lon2}} ->
          acc + Geocalc.distance_between([lat1, lon1], [lat2, lon2])

        _ ->
          acc
      end
    end)
  end

  defp parse_maxspeed(nil), do: nil
  defp parse_maxspeed(val) when is_integer(val), do: val

  defp parse_maxspeed(val) when is_binary(val) do
    case Regex.run(~r/^\d+/, val) do
      [digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp parse_lanes(nil), do: nil
  defp parse_lanes(val) when is_integer(val), do: val

  defp parse_lanes(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> nil
    end
  end
end
