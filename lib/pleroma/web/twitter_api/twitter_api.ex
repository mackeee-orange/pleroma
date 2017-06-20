defmodule Pleroma.Web.TwitterAPI.TwitterAPI do
  alias Pleroma.{User, Activity, Repo, Object}
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Formatter

  import Pleroma.Web.TwitterAPI.Utils

  def to_for_user_and_mentions(user, mentions, inReplyTo) do
    default_to = [
      User.ap_followers(user),
      "https://www.w3.org/ns/activitystreams#Public"
    ]

    to = default_to ++ Enum.map(mentions, fn ({_, %{ap_id: ap_id}}) -> ap_id end)
    if inReplyTo do
      Enum.uniq([inReplyTo.data["actor"] | to])
    else
      to
    end
  end

  def get_replied_to_activity(id) when not is_nil(id) do
    Repo.get(Activity, id)
  end

  def get_replied_to_activity(_), do: nil

  def create_status(%User{} = user, %{"status" => status} = data) do
    with attachments <- attachments_from_ids(data["media_ids"]),
         mentions <- Formatter.parse_mentions(status),
         inReplyTo <- get_replied_to_activity(data["in_reply_to_status_id"]),
         to <- to_for_user_and_mentions(user, mentions, inReplyTo),
         content_html <- make_content_html(status, mentions, attachments),
         context <- make_context(inReplyTo),
         tags <- Formatter.parse_tags(status),
         object <- make_note_data(user.ap_id, to, context, content_html, attachments, inReplyTo, tags) do
      ActivityPub.create(to, user, context, object)
    end
  end

  def favorite(%User{} = user, %Activity{data: %{"object" => object}} = activity) do
    object = Object.get_by_ap_id(object["id"])

    {:ok, _like_activity, object} = ActivityPub.like(user, object)
    new_data = activity.data
    |> Map.put("object", object.data)

    status = %{activity | data: new_data}
    {:ok, status}
  end

  def unfavorite(%User{} = user, %Activity{data: %{"object" => object}} = activity) do
    object = Object.get_by_ap_id(object["id"])

    {:ok, object} = ActivityPub.unlike(user, object)
    new_data = activity.data
    |> Map.put("object", object.data)

    status = %{activity | data: new_data}
    {:ok, status}
  end

  def retweet(%User{} = user, %Activity{data: %{"object" => object}} = activity) do
    object = Object.get_by_ap_id(object["id"])

    {:ok, _announce_activity, object} = ActivityPub.announce(user, object)
    new_data = activity.data
    |> Map.put("object", object.data)

    status = %{activity | data: new_data}
    {:ok, status}
  end

  def upload(%Plug.Upload{} = file, format \\ "xml") do
    {:ok, object} = ActivityPub.upload(file)

    url = List.first(object.data["url"])
    href = url["href"]
    type = url["mediaType"]

    case format do
      "xml" ->
        # Fake this as good as possible...
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rsp stat="ok" xmlns:atom="http://www.w3.org/2005/Atom">
        <mediaid>#{object.id}</mediaid>
        <media_id>#{object.id}</media_id>
        <media_id_string>#{object.id}</media_id_string>
        <media_url>#{href}</media_url>
        <mediaurl>#{href}</mediaurl>
        <atom:link rel="enclosure" href="#{href}" type="#{type}"></atom:link>
        </rsp>
        """
      "json" ->
        %{
          media_id: object.id,
          media_id_string: "#{object.id}}",
          media_url: href,
          size: 0
        } |> Poison.encode!
    end
  end

  def get_by_id_or_nickname(id_or_nickname) do
    if !is_integer(id_or_nickname) && :error == Integer.parse(id_or_nickname) do
      Repo.get_by(User, nickname: id_or_nickname)
    else
      Repo.get(User, id_or_nickname)
    end
  end

  def context_to_conversation_id(context) do
    with %Object{id: id} <- Object.get_cached_by_ap_id(context) do
      id
      else _e ->
        changeset = Object.context_mapping(context)
        case Repo.insert(changeset) do
          {:ok, %{id: id}} -> id
          # This should be solved by an upsert, but it seems ecto
          # has problems accessing the constraint inside the jsonb.
          {:error, _} -> Object.get_cached_by_ap_id(context).id
        end
    end
  end

  def conversation_id_to_context(id) do
    with %Object{data: %{"id" => context}} <- Repo.get(Object, id) do
      context
    else _e ->
      {:error, "No such conversation"}
    end
  end
end
