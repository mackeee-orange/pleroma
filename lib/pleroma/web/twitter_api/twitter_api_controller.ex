defmodule Pleroma.Web.TwitterAPI.Controller do
  use Pleroma.Web, :controller
  alias Pleroma.Web.TwitterAPI.{ErrorView, StatusView, TwitterAPI}
  alias Pleroma.{Repo, Activity, User}
  alias Pleroma.Web.ActivityPub.ActivityPub

  def status_update(%{assigns: %{user: user}} = conn, %{"status" => status_text} = status_data) do
    l = status_text |> String.trim |> String.length
    if l > 0 && l < 5000 do
      media_ids = extract_media_ids(status_data)
      {:ok, activity} = TwitterAPI.create_status(user, Map.put(status_data, "media_ids",  media_ids))
      render(conn, StatusView, "show.json", %{activity: activity})
    else
      empty_status_reply(conn)
    end
  end

  def status_update(conn, _status_data) do
    empty_status_reply(conn)
  end

  defp empty_status_reply(conn) do
    conn
    |> put_status(:bad_request)
    |> render(ErrorView, "error.json", %{request_path: conn.request_path, message: "Client must provide a 'status' parameter with a value."})
  end

  defp extract_media_ids(status_data) do
    with media_ids when not is_nil(media_ids) <- status_data["media_ids"],
         split_ids <- String.split(media_ids, ","),
         clean_ids <- Enum.reject(split_ids, fn (id) -> String.length(id) == 0 end)
      do
        clean_ids
      else _e -> []
    end
  end

  def public_and_external_timeline(conn, params) do
    activities = ActivityPub.fetch_public_activities(params)
    render(conn, StatusView, "timeline.json", %{activities: activities})
  end

  def public_timeline(conn, params) do
    params = Map.put(params, "local_only", true)
    activities = ActivityPub.fetch_public_activities(params)
    render(conn, StatusView, "timeline.json", %{activities: activities})
  end

  def friends_timeline(%{assigns: %{user: user}} = conn, params) do
    activities = ActivityPub.fetch_activities([user.ap_id | user.following], params)
    render(conn, StatusView, "timeline.json", %{activities: activities})
  end

  def user_timeline(%{assigns: %{user: user}} = conn, params) do
    case User.get_by_params(user, params) do
      {:ok, target_user} ->
        params = Map.merge(params, %{"actor_id" => target_user.ap_id})
        activities = ActivityPub.fetch_activities([], params)
        render(conn, StatusView, "timeline.json", %{activities: activities, for: user})
      {status, msg} ->
        conn
        |> put_status(status)
        |> render(ErrorView, "error.json", %{request_path: conn.request_path, message: msg})
    end
  end

  def mentions_timeline(%{assigns: %{user: user}} = conn, params) do
    activities = ActivityPub.fetch_activities([user.ap_id], params)
    render(conn, StatusView, "timeline.json", %{activities: activities, for: user})
  end

  def fetch_status(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    with %Activity{} = activity <- Repo.get(Activity, id) do
      render(conn, StatusView, "show.json", %{activity: activity, for: user})
    end
  end

  def fetch_conversation(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    id = String.to_integer(id)
    with context when is_binary(context) <- TwitterAPI.conversation_id_to_context(id),
         activities <- ActivityPub.fetch_activities_for_context(context)
    do
      render(conn, StatusView, "timeline.json", %{activities: activities, for: user})
    else _e ->
      json(conn, [])
    end
  end

  def upload(conn, %{"media" => media}) do
    response = TwitterAPI.upload(media)
    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, response)
  end

  def upload_json(conn, %{"media" => media}) do
    json(conn, TwitterAPI.upload(media, "json"))
  end

  def favorite(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    activity = Repo.get(Activity, id)
    {:ok, activity} = TwitterAPI.favorite(user, activity)
    render(conn, StatusView, "show.json", %{activity: activity, for: user})
  end

  def unfavorite(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    activity = Repo.get(Activity, id)
    {:ok, activity} = TwitterAPI.unfavorite(user, activity)
    render(conn, StatusView, "show.json", %{activity: activity, for: user})
  end

  def retweet(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    activity = Repo.get(Activity, id)
    if activity.data["actor"] == user.ap_id do
      conn
      |> put_status(:bad_request)
      |> render(ErrorView, "error.json", %{request_path: conn.request_path, message: "You cannot repeat your own notice."})
    else
      {:ok, activity} = TwitterAPI.retweet(user, activity)
      render(conn, StatusView, "show.json", %{activity: activity, for: user})
    end
  end

end
