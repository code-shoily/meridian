defmodule Meridian.Graph do
  @moduledoc """
  A spatial graph—`Yog.Graph` enriched with coordinate system metadata
  and an optional spatial bounding box.

  Implements `Enumerable` (iterates over `{id, data}` node tuples) and
  `Inspect` (compact `#Meridian.Graph<...>` representation).

  ## Fields

    * `graph` — the underlying `Yog.Graph.t()`
    * `crs` — coordinate reference system identifier (default `"EPSG:4326"`)
    * `srid` — numeric SRID when available (default `4326`)
    * `bounds` — bounding geometry (`%Geo.Polygon{}` or `nil`)

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g.crs
      "EPSG:4326"
      iex> g.srid
      4326

      iex> g = Meridian.Graph.new() |> Meridian.Graph.add_node(1, %{name: "A"})
      iex> Enum.to_list(g)
      [{1, %{name: "A"}}]
  """

  @type crs :: String.t()
  @type srid :: pos_integer() | nil

  @type t :: %__MODULE__{
          graph: Yog.Graph.t(),
          crs: crs(),
          srid: srid(),
          bounds: Geo.Polygon.t() | nil,
          calendar: list(map()) | nil
        }

  @enforce_keys [:graph]
  defstruct [
    :graph,
    :bounds,
    crs: "EPSG:4326",
    srid: 4326,
    calendar: nil
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty spatial graph.

  ## Options

    * `:kind` — `:directed` (default) or `:undirected`
    * `:crs` — CRS identifier string, defaults to `"EPSG:4326"`
    * `:srid` — numeric SRID, defaults to `4326`

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g.graph.kind
      :directed

      iex> g = Meridian.Graph.new(kind: :undirected, crs: "EPSG:3857")
      iex> g.crs
      "EPSG:3857"
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    kind = Keyword.get(opts, :kind, :directed)
    crs = Keyword.get(opts, :crs, "EPSG:4326")
    srid = Keyword.get(opts, :srid, 4326)

    %__MODULE__{
      graph: Yog.new(kind),
      crs: crs,
      srid: srid,
      bounds: nil
    }
  end

  @doc """
  Wraps an existing `Yog.Graph` as a spatial graph.

  ## Examples

      iex> yog = Yog.undirected() |> Yog.add_edge_ensure(1, 2, 10)
      iex> g = Meridian.Graph.from_yog(yog, crs: "EPSG:4326")
      iex> g.graph == yog
      true
  """
  @spec from_yog(Yog.Graph.t(), keyword()) :: t()
  def from_yog(%Yog.Graph{} = graph, opts \\ []) do
    crs = Keyword.get(opts, :crs, "EPSG:4326")
    srid = Keyword.get(opts, :srid, 4326)

    %__MODULE__{
      graph: graph,
      crs: crs,
      srid: srid,
      bounds: nil
    }
  end

  @doc """
  Unwraps a `Meridian.Graph` to its underlying `Yog.Graph`.

  ## Examples

      iex> g = Meridian.Graph.new() |> Meridian.Graph.add_node(1, "A")
      iex> %Yog.Graph{} = Meridian.Graph.to_yog(g)
  """
  @spec to_yog(t()) :: Yog.Graph.t()
  def to_yog(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all nodes as a map of `id => data`.
  """
  @spec nodes(t()) :: %{Yog.node_id() => any()}
  def nodes(%__MODULE__{graph: graph}), do: graph.nodes

  @doc """
  Returns all edges as a list of `{from, to, weight}` tuples.
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), any()}]
  def edges(%__MODULE__{graph: graph}), do: Yog.all_edges(graph)

  @doc """
  Returns the data associated with a node, or `nil` if the node does not exist.
  """
  @spec node(t(), Yog.node_id()) :: any() | nil
  def node(%__MODULE__{graph: graph}, id), do: Yog.node(graph, id)

  @doc """
  Returns the number of nodes in the spatial graph.
  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{graph: graph}), do: Yog.node_count(graph)

  @doc """
  Returns the number of edges in the spatial graph.
  """
  @spec edge_count(t()) :: non_neg_integer()
  def edge_count(%__MODULE__{graph: graph}), do: Yog.Graph.edge_count(graph)

  @doc """
  Checks if the graph contains a node with the given ID.
  """
  @spec has_node?(t(), Yog.node_id()) :: boolean()
  def has_node?(%__MODULE__{graph: graph}, id), do: Yog.has_node?(graph, id)

  @doc """
  Checks if a node has a `:geometry` key in its data.
  """
  @spec has_geometry?(t(), Yog.node_id()) :: boolean()
  def has_geometry?(%__MODULE__{graph: graph}, id) do
    case Yog.node(graph, id) do
      %{geometry: %Geo.Point{}} -> true
      %{geometry: %Geo.Polygon{}} -> true
      %{geometry: %Geo.LineString{}} -> true
      _ -> false
    end
  end

  @doc """
  Returns the kind of the underlying graph (`:directed` or `:undirected`).
  """
  @spec kind(t()) :: :directed | :undirected
  def kind(%__MODULE__{graph: graph}), do: graph.kind

  # ============================================================================
  # Modification
  # ============================================================================

  @doc """
  Adds a spatial node to the graph.

  `data` should typically contain a `:geometry` key with a `Geo` struct.

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> point = %Geo.Point{coordinates: {-79.3832, 43.6532}}
      iex> g = Meridian.Graph.add_node(g, :toronto, %{geometry: point, name: "Toronto"})
      iex> Meridian.Graph.node(g, :toronto).name
      "Toronto"
  """
  @spec add_node(t(), Yog.node_id(), map()) :: t()
  def add_node(%__MODULE__{graph: graph} = mg, id, data) do
    %{mg | graph: Yog.add_node(graph, id, data)}
  end

  @doc """
  Adds multiple nodes from an enumerable of `{id, data}` tuples or a map.

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = Meridian.Graph.add_nodes(g, a: %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
      iex> Meridian.Graph.node_count(g)
      1
  """
  @spec add_nodes(t(), Enumerable.t()) :: t()
  def add_nodes(%__MODULE__{graph: graph} = mg, nodes) do
    new_graph =
      Enum.reduce(nodes, graph, fn
        {id, data}, g -> Yog.add_node(g, id, data)
        id, g when is_atom(id) or is_integer(id) or is_binary(id) -> Yog.add_node(g, id, %{})
      end)

    %{mg | graph: new_graph}
  end

  @doc """
  Updates a node's data by merging the given map into the existing data.

  Returns the updated graph. If the node does not exist, it is created.

  ## Examples

      iex> g = Meridian.Graph.new() |> Meridian.Graph.add_node(:a, %{name: "A"})
      iex> g = Meridian.Graph.update_node(g, :a, %{tags: [:highway]})
      iex> Meridian.Graph.node(g, :a).tags
      [:highway]
  """
  @spec update_node(t(), Yog.node_id(), map()) :: t()
  def update_node(%__MODULE__{graph: graph} = mg, id, new_data) do
    existing = Map.get(graph.nodes, id, %{})
    merged = Map.merge(existing, new_data)
    %{mg | graph: Yog.add_node(graph, id, merged)}
  end

  @doc """
  Adds a spatial edge to the graph.

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> g = g |> Meridian.Graph.add_node(:a, %{}) |> Meridian.Graph.add_node(:b, %{})
      iex> {:ok, g} = Meridian.Graph.add_edge(g, :a, :b, %{distance: 10.5})
      iex> g.graph.out_edges[:a][:b]
      %{distance: 10.5}
  """
  @spec add_edge(t(), Yog.node_id(), Yog.node_id(), any()) ::
          {:ok, t()} | {:error, String.t()}
  def add_edge(%__MODULE__{graph: graph} = mg, from, to, weight) do
    case Yog.add_edge(graph, from, to, weight) do
      {:ok, g} -> {:ok, %{mg | graph: g}}
      err -> err
    end
  end

  @doc """
  Adds a spatial edge to the graph, raising on error.
  """
  @spec add_edge!(t(), Yog.node_id(), Yog.node_id(), any()) :: t()
  def add_edge!(%__MODULE__{graph: graph} = mg, from, to, weight) do
    %{mg | graph: Yog.add_edge!(graph, from, to, weight)}
  end

  @doc """
  Ensures both endpoint nodes exist, then adds an edge.

  If `from` or `to` is not already in the graph, it is created with the
  supplied `default` node data. Existing nodes are left unchanged.
  """
  @spec add_edge_ensure(t(), Yog.node_id(), Yog.node_id(), any(), any()) :: t()
  def add_edge_ensure(%__MODULE__{graph: graph} = mg, from, to, weight, default \\ nil) do
    %{mg | graph: Yog.add_edge_ensure(graph, from, to, weight, default)}
  end

  @doc """
  Removes a node and all its connected edges.
  """
  @spec remove_node(t(), Yog.node_id()) :: t()
  def remove_node(%__MODULE__{graph: graph} = mg, id) do
    %{mg | graph: Yog.remove_node(graph, id), bounds: nil}
  end

  @doc """
  Removes an edge from the graph.
  """
  @spec remove_edge(t(), Yog.node_id(), Yog.node_id()) :: t()
  def remove_edge(%__MODULE__{graph: graph} = mg, from, to) do
    %{mg | graph: Yog.remove_edge(graph, from, to)}
  end

  @doc """
  Recomputes the bounding box from all node geometries.
  """
  @spec recompute_bounds(t()) :: t()
  def recompute_bounds(%__MODULE__{graph: graph} = mg) do
    bounds = Meridian.Geometry.envelope(graph)
    %{mg | bounds: bounds}
  end

  @doc """
  Merges another spatial graph into this one.

  Both graphs must share the same CRS. Nodes and edges from `other` are
  added; in case of node ID collisions, `other`'s data wins.

  ## Examples

      iex> a = Meridian.Graph.new() |> Meridian.Graph.add_node(1, %{name: "A"})
      iex> b = Meridian.Graph.new() |> Meridian.Graph.add_node(2, %{name: "B"}) |> Meridian.Graph.add_edge_ensure(2, 1, 5)
      iex> merged = Meridian.Graph.merge(a, b)
      iex> Meridian.Graph.node_count(merged)
      2
      iex> Meridian.Graph.edge_count(merged)
      1
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{crs: crs} = a, %__MODULE__{crs: crs} = b) do
    graph =
      b.graph.nodes
      |> Enum.reduce(a.graph, fn {id, data}, g ->
        Yog.add_node(g, id, data)
      end)
      |> then(fn g ->
        Enum.reduce(Yog.all_edges(b.graph), g, fn {from, to, weight}, acc ->
          Yog.add_edge_ensure(acc, from, to, weight)
        end)
      end)

    %{a | graph: graph, bounds: nil}
  end

  def merge(%__MODULE__{crs: crs_a}, %__MODULE__{crs: crs_b}) do
    raise ArgumentError,
          "cannot merge graphs with different CRS: #{inspect(crs_a)} vs #{inspect(crs_b)}"
  end
end

defimpl Enumerable, for: Meridian.Graph do
  @moduledoc """
  Enumerable implementation for `Meridian.Graph`.

  Iterates over nodes as `{id, data}` tuples, similar to `Map.to_list/1`.
  """

  def count(%Meridian.Graph{graph: %{nodes: nodes}}) do
    {:ok, map_size(nodes)}
  end

  def member?(%Meridian.Graph{graph: %{nodes: nodes}}, {id, data}) do
    {:ok, Map.get(nodes, id) == data}
  end

  def member?(%Meridian.Graph{}, _) do
    {:ok, false}
  end

  def reduce(%Meridian.Graph{graph: %{nodes: nodes}}, acc, fun) do
    Enumerable.reduce(nodes, acc, fun)
  end

  def slice(%Meridian.Graph{graph: %{nodes: nodes}}) do
    {:ok, map_size(nodes),
     fn start, length, _step ->
       nodes
       |> :maps.to_list()
       |> Enum.slice(start, length)
     end}
  end
end

defimpl Inspect, for: Meridian.Graph do
  @moduledoc """
  Inspect implementation for `Meridian.Graph`.

  Provides a compact representation showing CRS, node count, and edge count.

  ## Examples

      iex> g = Meridian.Graph.new()
      iex> inspect(g)
      "#Meridian.Graph<EPSG:4326, 0 nodes, 0 edges>"

      iex> g = Meridian.Graph.new(kind: :undirected) |> Meridian.Graph.add_node(1, "A")
      iex> inspect(g)
      "#Meridian.Graph<EPSG:4326, 1 node, 0 edges>"
  """

  import Inspect.Algebra

  def inspect(%Meridian.Graph{} = graph, _opts) do
    node_count = map_size(graph.graph.nodes)
    edge_count = Yog.Graph.edge_count(graph.graph)

    node_str = if node_count == 1, do: "node", else: "nodes"
    edge_str = if edge_count == 1, do: "edge", else: "edges"

    concat([
      "#Meridian.Graph<",
      graph.crs,
      ", ",
      "#{node_count} #{node_str}, ",
      "#{edge_count} #{edge_str}",
      ">"
    ])
  end
end
