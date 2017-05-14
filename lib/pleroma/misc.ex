defmodule Pleroma.Misc do
  def make_date do
    DateTime.utc_now() |> DateTime.to_iso8601
  end

  def to_boolean(false), do: false

  def to_boolean(nil), do: false

  def to_boolean(_), do: true
end
