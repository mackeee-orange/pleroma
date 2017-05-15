defmodule Pleroma.Web.TwitterAPI.MediaController do
  use Pleroma.Web, :controller
  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.ActivityPub

  def upload(conn, %{"media" => media = %Plug.Upload{}}) do
    {:ok, %Object{id: id, data: %{"url" => %{"href" => href, "type" => type}}}} =
      ActivityPub.upload(media)
    response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rsp stat="ok" xmlns:atom="http://www.w3.org/2005/Atom">
      <mediaid>#{id}</mediaid>
      <media_id>#{id}</media_id>
      <media_id_string>#{id}</media_id_string>
      <media_url>#{href}</media_url>
      <mediaurl>#{href}</mediaurl>
      <atom:link rel="enclosure" href="#{href}" type="#{type}"></atom:link>
      </rsp>
      """

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, response)
  end

  def upload_json(conn, %{"media" => media = %Plug.Upload{}}) do
    {:ok, %Object{id: id, data: %{"url" => %{"href" => href}}}} = ActivityPub.upload(media)

    json conn, %{
      media_id: id,
      media_id_string: "#{id}}",
      media_url: href,
      size: 0
    }
  end
end
