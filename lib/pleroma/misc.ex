defmodule Pleroma.Misc do
  def make_date do
    DateTime.utc_now() |> DateTime.to_iso8601
  end
end
