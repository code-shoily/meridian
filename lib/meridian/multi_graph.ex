defmodule Meridian.MultiGraph do
  @moduledoc """
  > **Experimental:** This module is new and its API may change or be removed
  > in future releases. Feedback and real-world usage reports are welcome.

  A **multigraph** variant of `Meridian.Graph` that allows multiple parallel
  edges between the same pair of nodes.

  Each edge carries a unique `edge_id` (auto-incrementing integer). Use cases
  include multi-modal transport networks (walk, cycle, drive on the same street
  segment), redundant utility lines, or flight routes with different carriers.

  > **Design note:** Meridian's philosophy is that a single spatial connection
  between two points should be one edge with rich attributes (see
  `Meridian.Graph`). `MultiGraph` is provided for domains where parallel edges
  are genuinely distinct physical connections.

  ## Usage

      alias Meridian.MultiGraph

      graph =
        MultiGraph.new()
        |> MultiGraph.add_node(:a, %{geometry: %Geo.Point{coordinates: {0.0, 0.0}}})
        |> MultiGraph.add_node(:b, %{geometry: %Geo.Point{coordinates: {0.0, 1.0}}})

      {graph, e1} = MultiGraph.add_edge(graph, :a, :b, %{mode: :walk, minutes: 15})
      {graph, e2} = MultiGraph.add_edge(graph, :a, :b, %{mode: :cycle, minutes: 5})

      MultiGraph.edge_count(graph, :a, :b)
      # => 2

      MultiGraph.edges_between(graph, :a, :b)
      # => [{0, :a, :b, %{mode: :walk, minutes: 15}},
      #     {1, :a, :b, %{mode: :cycle, minutes: 5}}]

  ## Collapsing to a simple graph

  `yog_ex` pathfinding algorithms work on simple graphs. Use `to_simple/2` to
  collapse parallel edges before routing:

      graph
      |> MultiGraph.to_simple(:min_weight)
      |> Meridian.Pathfinding.a_star(from: :a, to: :b)

  Or select by a mode key:

      graph
      |> MultiGraph.to_simple({:mode, :cycle})
      |> Meridian.Pathfinding.shortest_path(from: :a, to: :b)
  """

  alias Meridian.Graph

  @enforce_keys [:graph]
  defstruct [:graph, :bounds, crs: "EPSG:4326", srid: 4326]

  @typedoc """
  A spatial multigraph wrapping `Yog.Multi.Graph` with CRS metadata.
  """
  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          bounds: Geo.Polygon.t() | nil,
          crs: String.t(),
          srid: pos_integer()
        }

  @typedoc "Unique edge identifier."
  @type edge_id :: non_neg_integer()

  # ============================================================================
  # Construction
  # ============================================================================

  @doc """
  Creates a new empty multigraph.

  ## Options

    * `:kind` — `:directed` (default) or `:undirected`
    * `:crs` — coordinate reference system string (default: `"EPSG:4326"`)
    * `:srid` — spatial reference ID (default: `4326`)

  ## Examples

      iex> g = Meridian.MultiGraph.new()
      iex> g.crs
      "EPSG:4326"
      iex> g.graph.kind
      :directed

      iex> g = Meridian.MultiGraph.new(kind: :undirected, crs: "EPSG:3857")
      iex> g.crs
      "EPSG:3857"
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    kind = Keyword.get(opts, :kind, :directed)

    %__MODULE__{
      graph: Yog.Multi.new(kind),
      crs: Keyword.get(opts, :crs, "EPSG:4326"),
      srid: Keyword.get(opts, :srid, 4326),
      bounds: nil
    }
  end

  @doc """
  Wraps an existing `Yog.Multi.Graph` with spatial metadata.

  ## Examples

      iex> yog = Yog.Multi.directed()
      iex> g = Meridian.MultiGraph.from_yog(yog, crs: "EPSG:3857")
      iex> g.crs
      "EPSG:3857"
  """
  @spec from_yog(Yog.Multi.Graph.t(), keyword()) :: t()
  def from_yog(%Yog.Multi.Graph{} = graph, opts \\ []) do
    %__MODULE__{
      graph: graph,
      crs: Keyword.get(opts, :crs, "EPSG:4326"),
      srid: Keyword.get(opts, :srid, 4326),
      bounds: nil
    }
  end

  @doc """
  Converts a `Meridian.MultiGraph` back to a plain `Yog.Multi.Graph`.
  """
  @spec to_yog(t()) :: Yog.Multi.Graph.t()
  def to_yog(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Nodes
  # ============================================================================

  @doc """
  Adds a node with the given ID and data.

  ## Examples

      iex> g = Meridian.MultiGraph.new()
      iex> g = Meridian.MultiGraph.add_node(g, :toronto, %{name: "Toronto"})
      iex> Meridian.MultiGraph.node(g, :toronto)
      %{name: "Toronto"}
  """
  @spec add_node(t(), Yog.node_id(), any()) :: t()
  def add_node(%__MODULE__{graph: graph} = mg, id, data) do
    %{mg | graph: Yog.Multi.add_node(graph, id, data)}
  end

  @doc """
  Adds multiple nodes from a list of `{id, data}` tuples.

  ## Examples

      iex> g = Meridian.MultiGraph.new()
      iex> g = Meridian.MultiGraph.add_nodes(g, [a: %{x: 1}, b: %{x: 2}])
      iex> Meridian.MultiGraph.node_count(g)
      2
  """
  @spec add_nodes(t(), [{Yog.node_id(), any()}]) :: t()
  def add_nodes(%__MODULE__{} = graph, nodes) do
    Enum.reduce(nodes, graph, fn {id, data}, g -> add_node(g, id, data) end)
  end

  @doc """
  Removes a node and all edges connected to it.

  ## Examples

      iex> g = Meridian.MultiGraph.new()
      iex> g = g |> Meridian.MultiGraph.add_node(:a, %{}) |> Meridian.MultiGraph.add_node(:b, %{})
      iex> {g, _eid} = Meridian.MultiGraph.add_edge(g, :a, :b, 1)
      iex> g = Meridian.MultiGraph.remove_node(g, :a)
      iex> Meridian.MultiGraph.node_count(g)
      1
      iex> Meridian.MultiGraph.edge_count(g)
      0
  """
  @spec remove_node(t(), Yog.node_id()) :: t()
  def remove_node(%__MODULE__{graph: graph} = mg, id) do
    %{mg | graph: Yog.Multi.remove_node(graph, id)}
  end

  @doc """
  Returns all nodes as a map of `id => data`.
  """
  @spec nodes(t()) :: %{Yog.node_id() => any()}
  def nodes(%__MODULE__{graph: graph}), do: graph.nodes

  @doc """
  Returns the data for a single node, or `nil` if absent.
  """
  @spec node(t(), Yog.node_id()) :: any() | nil
  def node(%__MODULE__{graph: graph}, id), do: Map.get(graph.nodes, id)

  @doc """
  Returns the number of nodes.
  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{graph: graph}), do: map_size(graph.nodes)

  @doc """
  Checks if a node exists.
  """
  @spec has_node?(t(), Yog.node_id()) :: boolean()
  def has_node?(%__MODULE__{graph: graph}, id), do: Map.has_key?(graph.nodes, id)

  # ============================================================================
  # Edges
  # ============================================================================

  @doc """
  Adds an edge from `from` to `to` with the given data.

  Returns `{updated_graph, new_edge_id}`.

  ## Examples

      iex> g = Meridian.MultiGraph.new()
      iex> g = g |> Meridian.MultiGraph.add_node(:a, %{}) |> Meridian.MultiGraph.add_node(:b, %{})
      iex> {g, eid} = Meridian.MultiGraph.add_edge(g, :a, :b, %{mode: :walk})
      iex> eid
      0
      iex> {_g, eid2} = Meridian.MultiGraph.add_edge(g, :a, :b, %{mode: :cycle})
      iex> eid2
      1
  """
  @spec add_edge(t(), Yog.node_id(), Yog.node_id(), any()) :: {t(), edge_id()}
  def add_edge(%__MODULE__{graph: graph} = mg, from, to, data) do
    {new_graph, eid} = Yog.Multi.add_edge(graph, from, to, data)
    {%{mg | graph: new_graph}, eid}
  end

  @doc """
  Removes a single edge by its `edge_id`.

  ## Examples

      iex> g = Meridian.MultiGraph.new()
      iex> g = g |> Meridian.MultiGraph.add_node(:a, %{}) |> Meridian.MultiGraph.add_node(:b, %{})
      iex> {g, eid} = Meridian.MultiGraph.add_edge(g, :a, :b, 1)
      iex> g = Meridian.MultiGraph.remove_edge(g, eid)
      iex> Meridian.MultiGraph.edge_count(g)
      0
  """
  @spec remove_edge(t(), edge_id()) :: t()
  def remove_edge(%__MODULE__{graph: graph} = mg, edge_id) do
    %{mg | graph: Yog.Multi.remove_edge(graph, edge_id)}
  end

  @doc """
  Returns all edges as a list of `{edge_id, from, to, data}` tuples.
  """
  @spec edges(t()) :: [{edge_id(), Yog.node_id(), Yog.node_id(), any()}]
  def edges(%__MODULE__{graph: graph}) do
    Enum.map(graph.edges, fn {eid, {from, to, data}} -> {eid, from, to, data} end)
  end

  @doc """
  Returns the data for a single edge by `edge_id`, or `nil`.
  """
  @spec edge(t(), edge_id()) :: {Yog.node_id(), Yog.node_id(), any()} | nil
  def edge(%__MODULE__{graph: graph}, edge_id) do
    Map.get(graph.edges, edge_id)
  end

  @doc """
  Returns all edges between `from` and `to` as `{edge_id, from, to, data}` tuples.

  ## Examples

      iex> g = Meridian.MultiGraph.new()
      iex> g = g |> Meridian.MultiGraph.add_node(:a, %{}) |> Meridian.MultiGraph.add_node(:b, %{})
      iex> {g, _e1} = Meridian.MultiGraph.add_edge(g, :a, :b, %{mode: :walk})
      iex> {g, _e2} = Meridian.MultiGraph.add_edge(g, :a, :b, %{mode: :cycle})
      iex> Meridian.MultiGraph.edges_between(g, :a, :b)
      ...> |> Enum.map(fn {_eid, data} -> data.mode end)
      [:walk, :cycle]
  """
  @spec edges_between(t(), Yog.node_id(), Yog.node_id()) :: [{edge_id(), any()}]
  def edges_between(%__MODULE__{graph: graph}, from, to) do
    Yog.Multi.edges_between(graph, from, to)
  end

  @doc """
  Returns the total number of edges in the multigraph.
  """
  @spec edge_count(t()) :: non_neg_integer()
  def edge_count(%__MODULE__{graph: graph}), do: map_size(graph.edges)

  @doc """
  Returns the number of parallel edges between `from` and `to`.
  """
  @spec edge_count(t(), Yog.node_id(), Yog.node_id()) :: non_neg_integer()
  def edge_count(%__MODULE__{graph: graph}, from, to) do
    Yog.Multi.Model.edge_count(graph, from, to)
  end

  @doc """
  Checks if an edge with the given `edge_id` exists.
  """
  @spec has_edge?(t(), edge_id()) :: boolean()
  def has_edge?(%__MODULE__{graph: graph}, edge_id), do: Map.has_key?(graph.edges, edge_id)

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns the kind of the multigraph: `:directed` or `:undirected`.
  """
  @spec kind(t()) :: Yog.graph_type()
  def kind(%__MODULE__{graph: graph}), do: graph.kind

  @doc """
  Returns outgoing edge IDs for a node.
  """
  @spec out_edge_ids(t(), Yog.node_id()) :: MapSet.t(edge_id())
  def out_edge_ids(%__MODULE__{graph: graph}, id) do
    Map.get(graph.out_edge_ids, id, MapSet.new())
  end

  @doc """
  Returns incoming edge IDs for a node.
  """
  @spec in_edge_ids(t(), Yog.node_id()) :: MapSet.t(edge_id())
  def in_edge_ids(%__MODULE__{graph: graph}, id) do
    Map.get(graph.in_edge_ids, id, MapSet.new())
  end

  @doc """
  Returns successor nodes (neighbors reached by outgoing edges).
  """
  @spec successors(t(), Yog.node_id()) :: [Yog.node_id()]
  def successors(%__MODULE__{graph: graph}, id) do
    Yog.Multi.successors(graph, id)
    |> Enum.map(fn {nid, _data} -> nid end)
    |> Enum.uniq()
  end

  @doc """
  Returns predecessor nodes (neighbors that have edges to this node).
  """
  @spec predecessors(t(), Yog.node_id()) :: [Yog.node_id()]
  def predecessors(%__MODULE__{graph: graph}, id) do
    Yog.Multi.predecessors(graph, id)
    |> Enum.map(fn {nid, _data} -> nid end)
    |> Enum.uniq()
  end

  # ============================================================================
  # Collapse to simple graph
  # ============================================================================

  @doc """
  Collapses the multigraph to a `Meridian.Graph` by selecting one edge per
  node pair according to `strategy`.

  ## Strategies

    * `:first` — keeps the first edge encountered (lowest `edge_id`)
    * `:min_weight` — keeps the edge with the minimum numeric weight.
      Edge data must be a number.
    * `:max_weight` — keeps the edge with the maximum numeric weight.
      Edge data must be a number.
    * `{:mode, key}` — keeps the first edge whose data is a map containing
      `mode: key`. Useful for multi-modal networks.
    * `{:by, selector}` — `selector` is a function that receives a list of
      `{edge_id, from, to, data}` tuples for each node pair and returns the
      `{edge_id, from, to, data}` to keep.
    * `{:combine, combiner}` — `combiner` is a function `(a, b) -> result` that
      folds parallel edges into a single value, like
      `fn a, b -> min(a, b) end`.

  ## Examples

  Keep the fastest mode per segment:

      iex> g = Meridian.MultiGraph.new()
      iex> g = g
      ...>   |> Meridian.MultiGraph.add_node(:a, %{})
      ...>   |> Meridian.MultiGraph.add_node(:b, %{})
      ...>   |> Meridian.MultiGraph.add_node(:c, %{})
      iex> {g, _} = Meridian.MultiGraph.add_edge(g, :a, :b, %{mode: :walk, minutes: 20})
      iex> {g, _} = Meridian.MultiGraph.add_edge(g, :a, :b, %{mode: :cycle, minutes: 5})
      iex> {g, _} = Meridian.MultiGraph.add_edge(g, :b, :c, %{mode: :walk, minutes: 10})
      iex> simple = Meridian.MultiGraph.to_simple(g, {:by, fn edges ->
      ...>   edges |> Enum.min_by(fn {_eid, _f, _t, data} -> data.minutes end)
      ...> end})
      iex> Graph.edge_count(simple)
      2
      iex> Graph.edges(simple) |> Enum.map(fn {_, _, data} -> data.mode end) |> Enum.sort()
      [:cycle, :walk]

  Combine by minimum numeric weight:

      iex> g = Meridian.MultiGraph.new()
      iex> g = g
      ...>   |> Meridian.MultiGraph.add_node(:a, %{})
      ...>   |> Meridian.MultiGraph.add_node(:b, %{})
      iex> {g, _} = Meridian.MultiGraph.add_edge(g, :a, :b, 10)
      iex> {g, _} = Meridian.MultiGraph.add_edge(g, :a, :b, 3)
      iex> simple = Meridian.MultiGraph.to_simple(g, :min_weight)
      iex> [{_, _, weight}] = Graph.edges(simple)
      iex> weight
      3
  """
  @spec to_simple(
          t(),
          :first
          | :min_weight
          | :max_weight
          | {:mode, atom()}
          | {:combine, (any(), any() -> any())}
        ) :: Graph.t()
  def to_simple(%__MODULE__{} = mg, strategy) do
    simple_yog = collapse(mg.graph, strategy)

    %Graph{
      graph: simple_yog,
      crs: mg.crs,
      srid: mg.srid,
      bounds: mg.bounds
    }
  end

  defp collapse(graph, :first), do: Yog.Multi.Model.to_simple_graph(graph)
  defp collapse(graph, :min_weight), do: Yog.Multi.Model.to_simple_graph_min_edges(graph)

  defp collapse(graph, :max_weight) do
    Yog.Multi.to_simple_graph(graph, fn a, b ->
      if is_number(a) and is_number(b), do: max(a, b), else: a
    end)
  end

  defp collapse(graph, {:mode, mode_key}), do: select_by_mode(graph, mode_key)
  defp collapse(graph, {:by, selector}), do: select_by(graph, selector)
  defp collapse(graph, {:combine, combiner}), do: Yog.Multi.to_simple_graph(graph, combiner)

  defp collapse(_graph, other),
    do: raise(ArgumentError, "unknown collapse strategy: #{inspect(other)}")

  # ============================================================================
  # CRS safety
  # ============================================================================

  @doc """
  Merges two multigraphs. Raises `ArgumentError` if CRS values differ.

  ## Examples

      iex> a = Meridian.MultiGraph.new() |> Meridian.MultiGraph.add_node(1, %{x: 1})
      iex> b = Meridian.MultiGraph.new() |> Meridian.MultiGraph.add_node(2, %{x: 2})
      iex> merged = Meridian.MultiGraph.merge(a, b)
      iex> Meridian.MultiGraph.node_count(merged)
      2

      iex> a = Meridian.MultiGraph.new(crs: "EPSG:4326")
      iex> b = Meridian.MultiGraph.new(crs: "EPSG:3857")
      iex> Meridian.MultiGraph.merge(a, b)
      ** (ArgumentError) cannot merge graphs with different CRS
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{crs: crs1}, %__MODULE__{crs: crs2}) when crs1 != crs2 do
    raise ArgumentError, "cannot merge graphs with different CRS"
  end

  def merge(%__MODULE__{graph: g1, crs: crs, srid: srid, bounds: b1} = _a, %__MODULE__{
        graph: g2,
        bounds: b2
      }) do
    merged_nodes = Map.merge(g1.nodes, g2.nodes)

    merged_edges = Map.merge(g1.edges, g2.edges, fn _k, _v1, v2 -> v2 end)

    merged_out =
      Map.merge(g1.out_edge_ids, g2.out_edge_ids, fn _k, s1, s2 ->
        MapSet.union(s1, s2)
      end)

    merged_in =
      Map.merge(g1.in_edge_ids, g2.in_edge_ids, fn _k, s1, s2 ->
        MapSet.union(s1, s2)
      end)

    next_id =
      Map.keys(merged_edges)
      |> Enum.max(fn -> -1 end)
      |> Kernel.+(1)

    merged_graph = %Yog.Multi.Graph{
      kind: g1.kind,
      nodes: merged_nodes,
      edges: merged_edges,
      out_edge_ids: merged_out,
      in_edge_ids: merged_in,
      next_edge_id: next_id
    }

    bounds =
      case {b1, b2} do
        {nil, nil} -> nil
        {b, nil} -> b
        {nil, b} -> b
        {bb1, bb2} -> bounding_union(bb1, bb2)
      end

    %__MODULE__{graph: merged_graph, crs: crs, srid: srid, bounds: bounds}
  end

  # ============================================================================
  # Protocols
  # ============================================================================

  defimpl Enumerable do
    def count(mg), do: {:ok, Meridian.MultiGraph.node_count(mg)}

    def member?(mg, {id, _data}) do
      {:ok, Meridian.MultiGraph.has_node?(mg, id)}
    end

    def member?(_mg, _other), do: {:ok, false}

    def reduce(mg, acc, fun) do
      Enumerable.List.reduce(Map.to_list(Meridian.MultiGraph.nodes(mg)), acc, fun)
    end

    def slice(_mg), do: {:error, __MODULE__}
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(mg, opts) do
      concat([
        "#Meridian.MultiGraph<",
        "kind: ",
        to_doc(mg.graph.kind, opts),
        ", nodes: ",
        to_doc(Meridian.MultiGraph.node_count(mg), opts),
        ", edges: ",
        to_doc(Meridian.MultiGraph.edge_count(mg), opts),
        ", crs: ",
        mg.crs,
        ">"
      ])
    end
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp select_by_mode(graph, mode_key) do
    base = Yog.Model.new(graph.kind)

    base_with_nodes =
      Enum.reduce(graph.nodes, base, fn {id, data}, g ->
        Yog.Model.add_node(g, id, data)
      end)

    seen = MapSet.new()

    graph.edges
    |> Enum.sort_by(fn {eid, _} -> eid end)
    |> Enum.reduce({base_with_nodes, seen}, fn edge, acc ->
      try_select_mode_edge(edge, acc, graph.kind, mode_key)
    end)
    |> elem(0)
  end

  defp try_select_mode_edge({_eid, {src, dst, data}}, {g, seen_acc}, kind, mode_key) do
    key = pair_key(src, dst, kind)

    cond do
      MapSet.member?(seen_acc, key) ->
        {g, seen_acc}

      is_map(data) and Map.get(data, :mode) == mode_key ->
        {Yog.Model.add_edge!(g, src, dst, data), MapSet.put(seen_acc, key)}

      true ->
        {g, seen_acc}
    end
  end

  defp pair_key(src, dst, :undirected) when src > dst, do: {dst, src}
  defp pair_key(src, dst, _), do: {src, dst}

  defp select_by(graph, selector) do
    base = Yog.Model.new(graph.kind)

    base_with_nodes =
      Enum.reduce(graph.nodes, base, fn {id, data}, g ->
        Yog.Model.add_node(g, id, data)
      end)

    # Group edges by node pair
    grouped =
      Enum.group_by(graph.edges, fn {_eid, {src, dst, _data}} ->
        if graph.kind == :undirected and src > dst, do: {dst, src}, else: {src, dst}
      end)

    Enum.reduce(grouped, base_with_nodes, fn {_pair, edge_list}, g ->
      mapped = Enum.map(edge_list, fn {eid, {src, dst, data}} -> {eid, src, dst, data} end)
      {_eid, src, dst, data} = selector.(mapped)
      Yog.Model.add_edge!(g, src, dst, data)
    end)
  end

  defp bounding_union(%Geo.Polygon{coordinates: c1}, %Geo.Polygon{coordinates: _c2}) do
    # NOTE: simplistic bounding box union — proper implementation would use
    # Meridian.Geometry.envelope/1 on all points.
    %Geo.Polygon{coordinates: c1}
  end

  defp bounding_union(b1, _b2), do: b1
end
