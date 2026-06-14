defmodule Meridian.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/code-shoily/meridian"

  def project do
    [
      app: :meridian,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], flags: [:no_opaque]],
      test_coverage: [tool: ExCoveralls],

      # Hex
      description: "Projection-aware spatial graphs on top of Yog",
      package: package(),

      # Docs
      name: "Meridian",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:yog_ex, "~> 0.98"},
      {:zog, path: "../zog", optional: true},
      {:zigler, "~> 0.16.0", runtime: false, optional: true},

      # Geometry & projections
      {:geo, "~> 3.6"},
      {:geocalc, "~> 0.8"},

      # Optional: H3 hexagonal grids (requires C NIF)
      {:h3, "~> 3.0", optional: true},

      # Optional: Geohash rectangular grids
      {:geohash, "~> 1.3", optional: true},

      # Optional: GeoJSON parsing / emitting
      {:jason, "~> 1.4", optional: true},

      # Optional: HTTP client for OSM / tile APIs
      {:req, "~> 0.5", optional: true},

      # Optional: OSM PBF file parser
      {:pbf_parser, "~> 0.1.2", optional: true},

      # Optional: MapLibre map rendering in Livebook
      {:maplibre, "~> 0.1", optional: true},
      {:kino_maplibre, "~> 0.1", optional: true},

      # Dev & Test
      {:ex_doc, "~> 0.39", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      name: :meridian,
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        {"livebooks/guides/getting_started.livemd",
         [filename: "getting_started", title: "Getting Started"]},
        {"livebooks/guides/osm_demo.livemd",
         [filename: "osm_demo", title: "OpenStreetMap & Pathfinding"]}
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          Meridian,
          Meridian.Graph,
          Meridian.MultiGraph
        ],
        "Coordinate Systems": [
          Meridian.CRS,
          Meridian.Geometry
        ],
        Builders: [
          ~r/Meridian\.Builder\./
        ],
        "I/O": [
          ~r/Meridian\.IO\./
        ],
        Rendering: [
          ~r/Meridian\.Render\./
        ]
      ]
    ]
  end
end
