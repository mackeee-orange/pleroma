defmodule Pleroma.Web.TwitterAPI.StatusView do
  use Pleroma.Web, :view
  alias Pleroma.{Activity, User, Utils}
  alias Pleroma.Web.TwitterAPI.{AttachmentView, TwitterAPI, UserView, Utils}

  def render(
    "show.json",
    %{
      activity: %Activity{
        data: %{"type" => "Announce", "id" => id, "object" => ap_id}
      },
    } = assigns) do
    {activity, user} = render_activity(assigns)

    [announced_activity = %Activity{}] = Activity.all_by_object_ap_id(ap_id)
    text = "#{user.nickname} retweeted a status."
    retweeted_status = render("show.json",
      Map.merge(assigns, %{activity: announced_activity})
    )

    Map.merge(activity, %{
                "retweeted_status" => retweeted_status,
                "statusnet_html" => text,
                "text" => text,
                "uri" => "tag:#{id}:objectType=note"
              })
  end

  def render(
    "show.json",
    %{activity: %Activity{
        data: %{"type" => "Like", "id" => id, "object" => liked_id}
      },
    } = assigns) do
    {activity, %User{nickname: nickname}} = render_activity(assigns)
    text = "#{nickname} favorited a status."
    [%Activity{id: liked_activity_id}] = Activity.all_by_object_ap_id(liked_id)

    Map.merge(activity, %{
                "in_reply_to_status_id" => liked_activity_id,
                "statusnet_html" => text,
                "text" => text,
                "uri" => "tag#{id}:objectType=Favorite"
              })
  end

  def render(
    "show.json",
    %{
      activity: %Activity{
        data: %{"type" => "Follow", "object" => followed_id}
      }
    } = assigns
  ) do
    {activity, %User{nickname: follower_name}} = render_activity(assigns)
    %User{nickname: followed_name} = User.get_cached_by_ap_id(followed_id)
    text = "#{follower_name} started following #{followed_name}"

    Map.merge(activity, %{
                "statusnet_html" => text,
                "text" => text
              })
  end

  def render(
    "show.json",
    %{
      activity: %Activity{
        data: %{
          "type" => "Create", "to" => to,
          "object" => %{
            "content" => content
          } = object
        }
      }
    } = assigns
  ) do
    announcement_count = object["announcement_count"] || 0
    repeated = Utils.to_boolean(assigns[:for] && assigns[:for].ap_id in (object["announcements"] || []))

    like_count = object["like_count"] || 0
    favorited = Utils.to_boolean(assigns[:for] && assigns[:for].ap_id in (object["likes"] || []))

    mentions = to
    |> Enum.map(fn (ap_id) -> User.get_cached_by_ap_id(ap_id) end)
    |> Enum.filter(&Utils.to_boolean/1)

    attentions = to
    |> Enum.map(fn (ap_id) -> Enum.find(mentions, fn(user) -> ap_id == user.ap_id end) end)
    |> Enum.filter(&Utils.to_boolean/1)
    |> Enum.map(fn (user) -> UserView.render("short.json", Map.merge(assigns, %{user: user})) end)

    attachments = (object["attachment"] || [])
    {activity, _user} = render_activity(assigns)
    Map.merge(activity, %{
                "attachments" => render_many(attachments, AttachmentView, "show.json"),
                "attentions" => attentions,
                "fave_num" => like_count,
                "favorited" => favorited,
                "in_reply_to_status_id" => object["inReplyToStatusId"],
                "is_post_verb" => true,
                "repeat_num" => announcement_count,
                "repeated" => repeated,
                "statusnet_html" => content,
                "text" => HtmlSanitizeEx.strip_tags(content)
             })
  end

  def render("timeline.json", %{activities: activities} = assigns) do
    render_many(activities, Pleroma.Web.TwitterAPI.StatusView, "show.json",
                Map.merge(assigns, %{as: :activity}))
  end

  def conversation_id(%Activity{data: %{"context" => context}}) do
    if context do
      TwitterAPI.context_to_conversation_id(context)
    else
      nil
    end
  end

  def conversation_id(%Activity{}), do: nil

  defp render_activity(assigns = %{
      activity: activity = %Activity{
        id: activity_id,
        data: %{"published" => created_at, "id" => external_url, "actor" => actor_id}
      },
    }) do
    user = %User{} = User.get_cached_by_ap_id(actor_id)
    {%{
      "attachments" => [],
      "attentions" => [],
      "created_at" => created_at |> Utils.date_to_asctime,
      "external_url" => external_url,
      "fave_num" => 0,
      "favorited" => false,
      "id" => activity_id,
      "in_reply_to_status_id" => nil,
      "is_local" => true,
      "is_post_verb" => false,
      "repeat_num" => 0,
      "repeated" => false,
      "statusnet_conversation_id" => conversation_id(activity),
      "source" => "api",
      "user" => UserView.render("show.json", Map.merge(assigns, %{user: user}))
    }, user}
  end
end
