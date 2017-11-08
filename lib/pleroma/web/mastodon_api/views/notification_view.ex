defmodule Pleroma.Web.MastodonAPI.NotificationView do
  use Pleroma.Web, :view
  alias Pleroma.{User, Activity}
  alias Pleroma.Web.MastodonAPI.{AccountView, StatusView}

  def render("notification.json", %{notification: notification}) do
    id = notification.id
    activity = notification.activity
    created_at = notification.inserted_at
    actor = User.get_cached_by_ap_id(activity.data["actor"])
    created_at = NaiveDateTime.to_iso8601(created_at)
    |> String.replace(~r/(\.\d+)?$/, ".000Z", global: false)
    case activity.data["type"] do
      "Create" ->
        %{id: id, type: "mention", created_at: created_at, account: AccountView.render("account.json", %{user: actor}), status: StatusView.render("status.json", %{activity: activity})}
      "Like" ->
        liked_activity = Activity.get_create_activity_by_object_ap_id(activity.data["object"])
        %{id: id, type: "favourite", created_at: created_at, account: AccountView.render("account.json", %{user: actor}), status: StatusView.render("status.json", %{activity: liked_activity})}
      "Announce" ->
        announced_activity = Activity.get_create_activity_by_object_ap_id(activity.data["object"])
        %{id: id, type: "reblog", created_at: created_at, account: AccountView.render("account.json", %{user: actor}), status: StatusView.render("status.json", %{activity: announced_activity})}
      "Follow" ->
        %{id: id, type: "follow", created_at: created_at, account: AccountView.render("account.json", %{user: actor})}
      _ -> nil
    end
  end
end
