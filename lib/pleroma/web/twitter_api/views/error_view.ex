defmodule Pleroma.Web.TwitterAPI.ErrorView do
  use Pleroma.Web, :view

  def render("error.json", %{request_path: request_path, message: message}) do
    %{error: message, request: request_path}
  end
end
