defmodule Pleroma.Web.TwitterAPI.TwitterAPITest do
  use Pleroma.DataCase
  alias Pleroma.Builders.{UserBuilder}
  alias Pleroma.Web.TwitterAPI.{StatusView, TwitterAPI, UserView, Utils}
  alias Pleroma.{Activity, User, Object, Repo}
  alias Pleroma.Web.ActivityPub.ActivityPub

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
      "status" => "Hello again, @shp.<script></script>\nThis is on another line. #2hu #epic #phantasmagoric",
      "media_ids" => [object.id]
    }

    { :ok, activity = %Activity{} } = TwitterAPI.create_status(user, input)

    assert get_in(activity.data, ["object", "content"]) == "Hello again, <a href='shp'>@shp</a>.<br>\nThis is on another line. #2hu #epic #phantasmagoric<br>\n<a href=\"http://example.org/image.jpg\" class='attachment'>image.jpg</a>"
    assert get_in(activity.data, ["object", "type"]) == "Note"
    assert get_in(activity.data, ["object", "actor"]) == user.ap_id
    assert get_in(activity.data, ["actor"]) == user.ap_id
    assert Enum.member?(get_in(activity.data, ["to"]), User.ap_followers(user))
    assert Enum.member?(get_in(activity.data, ["to"]), "https://www.w3.org/ns/activitystreams#Public")
    assert Enum.member?(get_in(activity.data, ["to"]), "shp")
    assert activity.local == true

    # hashtags
    assert activity.data["object"]["tag"] == ["2hu", "epic", "phantasmagoric"]

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

  test "get a user by params" do
    user1_result = {:ok, user1} = UserBuilder.insert(%{ap_id: "some id", email: "test@pleroma"})
    {:ok, user2} = UserBuilder.insert(%{ap_id: "some other id", nickname: "testname2", email: "test2@pleroma"})

    assert {:error, "You need to specify screen_name or user_id"} == TwitterAPI.get_user(nil, nil)
    assert user1_result == TwitterAPI.get_user(nil, %{"user_id" => user1.id})
    assert user1_result == TwitterAPI.get_user(nil, %{"user_id" => user1.nickname})
    assert user1_result == TwitterAPI.get_user(nil, %{"screen_name" => user1.nickname})
    assert user1_result == TwitterAPI.get_user(user1, nil)
    assert user1_result == TwitterAPI.get_user(user2, %{"user_id" => user1.id})
    assert user1_result == TwitterAPI.get_user(user2, %{"screen_name" => user1.nickname})
    assert {:error, "No user with such screen_name"} == TwitterAPI.get_user(nil, %{"screen_name" => "Satan"})
    assert {:error, "No user with such user_id"} == TwitterAPI.get_user(nil, %{"user_id" => 666})
  end

  test "Follow another user using user_id" do
    user = insert(:user)
    followed = insert(:user)

    {:ok, user, followed, _activity } = TwitterAPI.follow(user, %{"user_id" => followed.id})
    assert user.following == [User.ap_followers(followed)]

    { :error, msg } = TwitterAPI.follow(user, %{"user_id" => followed.id})
    assert msg == "Could not follow user: #{followed.nickname} is already on your list."
  end

  test "Follow another user using screen_name" do
    user = insert(:user)
    followed = insert(:user)

    {:ok, user, followed, _activity } = TwitterAPI.follow(user, %{"screen_name" => followed.nickname})
    assert user.following == [User.ap_followers(followed)]

    { :error, msg } = TwitterAPI.follow(user, %{"screen_name" => followed.nickname})
    assert msg == "Could not follow user: #{followed.nickname} is already on your list."
  end

  test "Unfollow another user using user_id" do
    unfollowed = insert(:user)
    user = insert(:user, %{following: [User.ap_followers(unfollowed)]})
    ActivityPub.follow(user, unfollowed)

    {:ok, user, unfollowed } = TwitterAPI.unfollow(user, %{"user_id" => unfollowed.id})
    assert user.following == []

    { :error, msg } = TwitterAPI.unfollow(user, %{"user_id" => unfollowed.id})
    assert msg == "Not subscribed!"
  end

  test "Unfollow another user using screen_name" do
    unfollowed = insert(:user)
    user = insert(:user, %{following: [User.ap_followers(unfollowed)]})

    ActivityPub.follow(user, unfollowed)

    {:ok, user, unfollowed } = TwitterAPI.unfollow(user, %{"screen_name" => unfollowed.nickname})
    assert user.following == []

    { :error, msg } = TwitterAPI.unfollow(user, %{"screen_name" => unfollowed.nickname})
    assert msg == "Not subscribed!"
  end

  test "upload a file" do
    file = %Plug.Upload{content_type: "image/jpg", path: Path.absname("test/fixtures/image.jpg"), filename: "an_image.jpg"}

    response = TwitterAPI.upload(file)

    assert is_binary(response)
  end

  test "it adds user links to an existing text" do
    text = "@gsimg According to @archaeme, that is @daggsy. Also hello @archaeme@archae.me"

    gsimg = insert(:user, %{nickname: "gsimg"})
    archaeme = insert(:user, %{nickname: "archaeme"})
    archaeme_remote = insert(:user, %{nickname: "archaeme@archae.me"})

    mentions = Pleroma.Formatter.parse_mentions(text)
    expected_text = "<a href='#{gsimg.ap_id}'>@gsimg</a> According to <a href='#{archaeme.ap_id}'>@archaeme</a>, that is @daggsy. Also hello <a href='#{archaeme_remote.ap_id}'>@archaeme</a>"

    assert Utils.add_user_links(text, mentions) == expected_text
  end

  test "it favorites a status, returns the updated status" do
    user = insert(:user)
    note_activity = insert(:note_activity)

    {:ok, status} = TwitterAPI.favorite(user, note_activity)
    updated_activity = Activity.get_by_ap_id(note_activity.data["id"])

    assert StatusView.render("show.json", %{activity: status}) == StatusView.render("show.json", %{activity: updated_activity}) # FIXME: was complaining about microseconds
  end

  test "it unfavorites a status, returns the updated status" do
    user = insert(:user)
    note_activity = insert(:note_activity)
    object = Object.get_by_ap_id(note_activity.data["object"]["id"])

    {:ok, _like_activity, _object } = ActivityPub.like(user, object)
    %Activity{data: %{"object" => object}} = Activity.get_by_ap_id(note_activity.data["id"])
    assert object["like_count"] == 1

    {:ok, %Activity{data: %{"object" => object}}} = TwitterAPI.unfavorite(user, note_activity)

    assert object["like_count"] == 0
  end

  test "it retweets a status and returns the retweet" do
    user = insert(:user)
    note_activity = insert(:note_activity)

    {:ok, status} = TwitterAPI.retweet(user, note_activity)
    updated_activity = Activity.get_by_ap_id(note_activity.data["id"])
    assert StatusView.render("show.json", %{activity: status}) == StatusView.render("show.json", %{activity: updated_activity}) # FIXME: was complaining about microseconds
  end

  test "it registers a new user and returns the user." do
    data = %{
      "nickname" => "lain",
      "email" => "lain@wired.jp",
      "fullname" => "lain iwakura",
      "bio" => "close the world.",
      "password" => "bear",
      "confirm" => "bear"
    }

    {:ok, user} = TwitterAPI.register_user(data)

    fetched_user = Repo.get_by(User, nickname: "lain")
    assert UserView.render("show.json", %{user: user}) == UserView.render("show.json", %{user: fetched_user})
  end

  test "it returns the error on registration problems" do
    data = %{
      "nickname" => "lain",
      "email" => "lain@wired.jp",
      "fullname" => "lain iwakura",
      "bio" => "close the world.",
      "password" => "bear"
    }

    {:error, error_object} = TwitterAPI.register_user(data)

    assert is_binary(error_object[:error])
    refute Repo.get_by(User, nickname: "lain")
  end

  test "it assigns an integer conversation_id" do
    note_activity = insert(:note_activity)
    assert is_number(StatusView.conversation_id(note_activity))
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

  describe "fetching a user by uri" do
    test "fetches a user by uri" do
      id = "https://mastodon.social/users/lambadalambda"
      user = insert(:user)
      {:ok, represented} = TwitterAPI.get_external_profile(user, id)
      remote = User.get_by_ap_id(id)

      assert represented == UserView.render("show.json", %{user: remote, for: user})

      # Also fetches the feed.
      assert Activity.get_create_activity_by_object_ap_id("tag:mastodon.social,2017-04-05:objectId=1641750:objectType=Status")
    end
  end
end
