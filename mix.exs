defmodule Muweb.Mixfile do
  use Mix.Project

  def project do
    [app: :muweb,
     version: "0.0.1",
     elixir: "~> 0.13.3 or ~> 0.14.0"]
  end

  def application do
    [mod: {Muweb, []}]
  end

  # no deps
  # --alco
end
