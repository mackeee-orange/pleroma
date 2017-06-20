defmodule Pleroma.Web.TwitterAPI.StatusViewTest do
  use Pleroma.DataCase
  alias Pleroma.{User, Activity, Object}
  alias Pleroma.Web.TwitterAPI.{AttachmentView, UserView, StatusView}
  alias Pleroma.Web.ActivityPub.ActivityPub
  import Pleroma.Factory

  test "an announce activity" do
    user = insert(:user)
    %Activity{data: %{"id" => note_ap_id, "object" => %{"id" => object_id}}} = insert(:note_activity)
    object = Object.get_by_ap_id(object_id)

    {:ok,
     announce_activity = %Activity{id: announce_id, data: %{"type" => "Announce"}},
     _object} = ActivityPub.announce(user, object)

    status = StatusView.render("show.json", %{activity: announce_activity, for: user})
    assert status["id"] == announce_id
    assert status["user"] == UserView.render("show.json", %{user: user, for: user})

    note_activity = Activity.get_by_ap_id(note_ap_id)
    retweeted_status = StatusView.render("show.json", %{activity: note_activity, for: user})
    assert retweeted_status["repeated"] == true
    assert retweeted_status["id"] == note_activity.id
    assert status["statusnet_conversation_id"] == retweeted_status["statusnet_conversation_id"]

    assert status["retweeted_status"] == retweeted_status
  end

  test "a like activity" do
    user = insert(:user)
    %Activity{id: note_id, data: %{"id" => note_ap_id, "object" => %{"id" => object_id}}} = insert(:note_activity)
    object = Object.get_by_ap_id(object_id)

    {:ok, like_activity = %Activity{id: like_id, data: %{"type" => "Like"}}, _object} = ActivityPub.like(user, object)
    status = StatusView.render("show.json", %{activity: like_activity})

    assert status["id"] == like_id
    assert status["in_reply_to_status_id"] == note_id

    note_activity = Activity.get_by_ap_id(note_ap_id)
    liked_status = StatusView.render("show.json", %{activity: note_activity, for: user})
    assert liked_status["favorited"] == true
  end

  test "an activity" do
    user = insert(:user, %{nickname: "dtluna"})
    #   {:ok, mentioned_user } = UserBuilder.insert(%{nickname: "shp", ap_id: "shp"})
    mentioned_user = insert(:user, %{nickname: "shp"})

    # {:ok, follower} = UserBuilder.insert(%{following: [User.ap_followers(user)]})
    follower = insert(:user, %{following: [User.ap_followers(user)]})

    object = %Object{
      data: %{
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
    }

    content_html = "Some content mentioning <a href='#{mentioned_user.ap_id}'>@shp</shp>"
    content = HtmlSanitizeEx.strip_tags(content_html)
    date = DateTime.from_naive!(~N[2016-05-24 13:26:08.003], "Etc/UTC") |> DateTime.to_iso8601

    {:ok, convo_object} = Object.context_mapping("2hu") |> Repo.insert

    activity = %Activity{
      id: 1,
      data: %{
        "type" => "Create",
        "id" => "id",
        "to" => [
          User.ap_followers(user),
          "https://www.w3.org/ns/activitystreams#Public",
          mentioned_user.ap_id
        ],
        "actor" => user.ap_id,
        "object" => %{
          "published" => date,
          "type" => "Note",
          "content" => content_html,
          "inReplyToStatusId" => 213123,
          "attachment" => [
            object
          ],
          "like_count" => 5,
          "announcement_count" => 3,
          "context" => "2hu"
        },
        "published" => date,
        "context" => "2hu"
      }
    }


    expected_status = %{
      "id" => activity.id,
      "user" => UserView.render("show.json", %{user: user, for: follower}),
      "is_local" => true,
      "statusnet_html" => content_html,
      "text" => content,
      "is_post_verb" => true,
      "created_at" => "Tue May 24 13:26:08 +0000 2016",
      "in_reply_to_status_id" => 213123,
      "statusnet_conversation_id" => convo_object.id,
      "attachments" => [
        AttachmentView.render("show.json", %{attachment: object})
      ],
      "attentions" => [
        UserView.render("short.json", %{user: mentioned_user})
      ],
      "fave_num" => 5,
      "repeat_num" => 3,
      "favorited" => false,
      "repeated" => false,
      "external_url" => activity.data["id"],
      "source" => "api"
    }

    assert StatusView.render("show.json", %{activity: activity, for: follower}) == expected_status
  end
end
