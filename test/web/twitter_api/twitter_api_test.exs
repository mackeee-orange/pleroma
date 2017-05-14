defmodule Pleroma.Web.TwitterAPI.TwitterAPITest do
  use Pleroma.DataCase
  alias Pleroma.Builders.{UserBuilder}
  alias Pleroma.Web.TwitterAPI.TwitterAPI
  alias Pleroma.{Activity, User, Object, Repo}

  import Pleroma.Factory

  test "create a status" do
    user = UserBuilder.build(%{ap_id: "142344"})
    _mentioned_user = UserBuilder.insert(%{nickname: "shp", ap_id: "shp"})

    object_data = %{
      "type" => "Image",
      "url" => [
        %{
          "type" => "Link",
          "mediaType" => "image/jpg",
          "href" => "http://example.org/image.jpg"
        }
      ],
      "uuid" => 1
    }

    object = Repo.insert!(%Object{data: object_data})

    input = %{
      "status" => "Hello again, @shp.<script></script>\nThis is on another line.",
      "media_ids" => [object.id]
    }

    { :ok, activity = %Activity{} } = TwitterAPI.create_status(user, input)

    assert get_in(activity.data, ["object", "content"]) == "Hello again, <a href='shp'>@shp</a>.<br>This is on another line.<br><a href='http://example.org/image.jpg' class='attachment'>http://example.org/image.jpg</a>"
    assert get_in(activity.data, ["object", "type"]) == "Note"
    assert get_in(activity.data, ["object", "actor"]) == user.ap_id
    assert get_in(activity.data, ["actor"]) == user.ap_id
    assert Enum.member?(get_in(activity.data, ["to"]), User.ap_followers(user))
    assert Enum.member?(get_in(activity.data, ["to"]), "https://www.w3.org/ns/activitystreams#Public")
    assert Enum.member?(get_in(activity.data, ["to"]), "shp")
    assert activity.local == true

    # Add a context
    assert is_binary(get_in(activity.data, ["context"]))
    assert is_binary(get_in(activity.data, ["object", "context"]))

    assert is_list(activity.data["object"]["attachment"])

    assert activity.data["object"] == Object.get_by_ap_id(activity.data["object"]["id"]).data
  end

  test "create a status that is a reply" do
    user = UserBuilder.build(%{ap_id: "some_cool_id"})
    input = %{
      "status" => "Hello again."
    }

    { :ok, activity = %Activity{} } = TwitterAPI.create_status(user, input)

    input = %{
      "status" => "Here's your (you).",
      "in_reply_to_status_id" => activity.id
    }

    { :ok, reply = %Activity{} } = TwitterAPI.create_status(user, input)

    assert get_in(reply.data, ["context"]) == get_in(activity.data, ["context"])
    assert get_in(reply.data, ["object", "context"]) == get_in(activity.data, ["object", "context"])
    assert get_in(reply.data, ["object", "inReplyTo"]) == get_in(activity.data, ["object", "id"])
    assert get_in(reply.data, ["object", "inReplyToStatusId"]) == activity.id
    assert Enum.member?(get_in(reply.data, ["to"]), "some_cool_id")
  end

  test "upload a file" do
    file = %Plug.Upload{content_type: "image/jpg", path: Path.absname("test/fixtures/image.jpg"), filename: "an_image.jpg"}

    response = TwitterAPI.upload(file)

    assert is_binary(response)
  end

  test "it can parse mentions and return the relevant users" do
    text = "@gsimg According to @archaeme , that is @daggsy."

    gsimg = insert(:user, %{nickname: "gsimg"})
    archaeme = insert(:user, %{nickname: "archaeme"})

    expected_result = [
      {"@gsimg", gsimg},
      {"@archaeme", archaeme}
    ]

    assert TwitterAPI.parse_mentions(text) == expected_result
  end

  test "it adds user links to an existing text" do
    text = "@gsimg According to @archaeme , that is @daggsy."

    gsimg = insert(:user, %{nickname: "gsimg"})
    archaeme = insert(:user, %{nickname: "archaeme"})

    mentions = TwitterAPI.parse_mentions(text)
    expected_text = "<a href='#{gsimg.ap_id}'>@gsimg</a> According to <a href='#{archaeme.ap_id}'>@archaeme</a> , that is @daggsy."

    assert TwitterAPI.add_user_links(text, mentions) == expected_text
  end

  setup do
    Supervisor.terminate_child(Pleroma.Supervisor, Cachex)
    Supervisor.restart_child(Pleroma.Supervisor, Cachex)
    :ok
  end

  describe "context_to_conversation_id" do
    test "creates a mapping object" do
      conversation_id = TwitterAPI.context_to_conversation_id("random context")
      object = Object.get_by_ap_id("random context")

      assert conversation_id == object.id
    end

    test "returns an existing mapping for an existing object" do
      {:ok, object} = Object.context_mapping("random context") |> Repo.insert
      conversation_id = TwitterAPI.context_to_conversation_id("random context")

      assert conversation_id == object.id
    end
  end
end
