defmodule Muweb.Util do
  @moduledoc false

  def strip_list([]), do: []
  def strip_list([""|rest]), do: strip_list(rest)
  def strip_list([h|rest]), do: [h|strip_list(rest)]
end
