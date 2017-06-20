defmodule Pleroma.Web.TwitterAPI.AttachmentViewTest do
  use Pleroma.DataCase

  alias Pleroma.Object
  alias Pleroma.Web.TwitterAPI.AttachmentView

  test "represent an image attachment" do
    object = %Object{
      id: 5,
      data: %{
        "type" => "Image",
        "url" => [
          %{
            "mediaType" => "sometype",
            "href" => "someurl"
          }
        ],
        "uuid" => 6
      }
    }

    expected_object = %{
      id: 6,
      url: "someurl",
      mimetype: "sometype",
      oembed: false
    }

    assert expected_object == AttachmentView.render("show.json", %{attachment: object})
  end
end
