defmodule Pleroma.Web.TwitterAPI.ErrorViewTest do
  use Pleroma.DataCase

  alias Pleroma.Web.TwitterAPI.ErrorView

  test "render an error" do
    path = "/labor_theory_of_value"
    message = "Labor theory of value is invalid!"
    map = %{request_path: path, message: message}
    expected_object = %{request: path, error: message}

    assert expected_object == ErrorView.render("error.json", map)
  end
end
