defmodule Pleroma.Web.TwitterAPI.AttachmentView do
  use Pleroma.Web, :view
  alias Pleroma.Object

  def render("show.json", %{attachment: %Object{data: data}}) do
    url = List.first(data["url"])
    %{
      url: url["href"],
      mimetype: url["mediaType"],
      id: data["uuid"],
      oembed: false
    }
  end
end
