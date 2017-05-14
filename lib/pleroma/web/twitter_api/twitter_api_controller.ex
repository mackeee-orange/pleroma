defmodule Pleroma.Web.TwitterAPI.Controller do
  use Pleroma.Web, :controller
  alias Pleroma.Web.TwitterAPI.TwitterAPI

  def upload(conn, %{"media" => media}) do
    response = TwitterAPI.upload(media)
    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, response)
  end

  def upload_json(conn, %{"media" => media}) do
    response = TwitterAPI.upload(media, "json")
    conn
    |> json_reply(200, response)
  end

  defp json_reply(conn, status, json) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, json)
  end
end
