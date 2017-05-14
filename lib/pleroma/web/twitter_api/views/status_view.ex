defmodule Pleroma.Web.TwitterAPI.StatusView do
  use Pleroma.Web, :view
  alias Pleroma.{Activity, User, Misc}
  alias Calendar.Strftime
  alias Pleroma.Web.TwitterAPI.{TwitterAPI, UserView, AttachmentView}

  def render(
    "show.json",
    assigns = %{
      activity: %Activity{
        data: %{"type" => "Announce", "id" => id, "object" => ap_id}
      },
    }) do
    {activity, user} = render_activity(assigns)

    announced_activity = Activity.get_by_ap_id(ap_id)
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
    assigns = %{activity: %Activity{
        data: %{"type" => "Like", "id" => id, "object" => liked_id}
      },
    }) do
    {activity, %User{nickname: nickname}} = render_activity(assigns)
    text = "#{nickname} favorited a status."

    %Activity{id: liked_activity_id} = Activity.get_by_ap_id(liked_id)

    Map.merge(activity, %{
                "in_reply_to_status_id" => liked_activity_id,
                "statusnet_html" => text,
                "text" => text,
                "uri" => "tag#{id}:objectType=Favorite"
              })
  end

  def render(
    "show.json",
    assigns = %{
      activity: %Activity{
        data: %{"type" => "Follow", "object" => followed_id}
      }
    }
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
    assigns = %{
      activity: %Activity{
        data: %{
          "type" => "Create", "to" => to,
          "object" => object = %{
            "content" => content
          }
        }
      }
    }
  ) do
    announcement_count = object["announcement_count"] || 0
    repeated = Misc.to_boolean(assigns[:for] && assigns[:for].ap_id in (object["announcements"] || []))

    like_count = object["like_count"] || 0
    favorited = Misc.to_boolean(assigns[:for] && assigns[:for].ap_id in (object["likes"] || []))

    mentions = assigns[:mentions] || []
    attentions = to
    |> Enum.map(fn (ap_id) -> Enum.find(mentions, fn(user) -> ap_id == user.ap_id end) end)
    |> Enum.filter(&Misc.to_boolean/1)
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

  def render("timeline.json", assigns = %{activities: activities}) do
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
        data: %{"published" => created_at, "id" => external_url, "actor" => actor_id}
      },
    }) do
    user = User.get_cached_by_ap_id(actor_id)
    {%{
      "attachments" => [],
      "attentions" => [],
      "created_at" => created_at |> date_to_asctime,
      "external_url" => external_url,
      "fave_num" => 0,
      "favorited" => false,
      "id" => activity.id,
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

  defp date_to_asctime(date) do
    with {:ok, date, _offset} <- date |> DateTime.from_iso8601 do
      Strftime.strftime!(date, "%a %b %d %H:%M:%S %z %Y")
    else _e ->
        ""
    end
  end
end
