defmodule ExLCD.Mixfile do
  use Mix.Project

  def project do
    [app: :ex_lcd,
     version: "0.4.0",
     elixir: "~> 1.4",
     description: description(),
     package: package(),
     docs: [extras: ["README.md"]],
     aliases: ["docs": ["docs", &copy_images/1]],
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
     deps: deps()]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(_), do: ["test/support", "lib"]

  def application do
    []
  end

  defp deps do
    [
      # {:elixir_ale, "~> 0.6.0", only: :prod},
      {:ex_doc, "~> 0.11", only: [:dev]}
    ]
  end

  defp description do
    """
    Hex package to use character matrix LCD displays including HD44780
    in your Elixir/nerves projects. Uses elixir_ale for IO.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Erik Petersen"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/cthree/ex_lcd"}
    ]
  end

  # Copy the images referenced by docs, since ex_doc doesn't do this.
  defp copy_images(_) do
    File.cp_r "assets", "doc/assets"
  end
end
