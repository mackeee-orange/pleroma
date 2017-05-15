defmodule Pleroma.Web.TwitterAPI.StatusController do
  use Pleroma.Web, :controller
  alias Pleroma.{Activity, Repo, Object, User}
  alias Pleroma.Web.TwitterAPI.{ErrorView, TwitterAPI, UserController}
  alias Pleroma.Web.ActivityPub.ActivityPub

  def status_update(%{assigns: %{user: user}} = conn, %{"status" => status_text} = status_data) do
    l = status_text |> String.trim |> String.length
    if l > 0 && l < 5000 do
      media_ids = extract_media_ids(status_data)
      {:ok, activity} = TwitterAPI.create_status(user, Map.put(status_data, "media_ids",  media_ids))
      render(conn, "show.json", %{activity: activity, for: user})
    else
      empty_status_reply(conn)
    end
  end

  def status_update(conn, _status_data) do
    empty_status_reply(conn)
  end

  defp empty_status_reply(conn) do
    message = "Client must provide a 'status' parameter with a value."
    conn
    |> put_status(:bad_request)
    |> render(ErrorView, "error.json", %{request_path: conn.request_path, message: message})
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

  def public_and_external_timeline(%{assigns: %{user: user}} = conn, params) do
    activities = ActivityPub.fetch_public_activities(params)
    render(conn, "timeline.json", %{activities: activities, for: user})
  end

  def public_timeline(%{assigns: %{user: user}} = conn, params) do
    activities = ActivityPub.fetch_public_activities(Map.put(params, "local_only", true))
    render(conn, "timeline.json", %{activities: activities, for: user})
  end

  def friends_timeline(%{assigns: %{user: user}} = conn, params) do
    activities = ActivityPub.fetch_activities([user.ap_id | user.following], params)
    render(conn, "timeline.json", %{activities: activities, for: user})
  end

  def user_timeline(conn, params) do
    case UserController.find_user(conn, params) do
      {:error, response} -> response

      {:ok, user = %User{ap_id: ap_id}} ->
        activities = ActivityPub.fetch_activities([], Map.merge(params, %{"actor_id" => ap_id}))
        render(conn, "timeline.json", %{activities: activities, for: user})
    end
  end

  def mentions_timeline(%{assigns: %{user: user}} = conn, params) do
    activities = ActivityPub.fetch_activities([user.ap_id], params)
    render(conn, "timeline.json", %{activities: activities, for: user})
  end

  def fetch_status(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    case find_activity(conn, id) do
      {:not_found, response} -> response
      {:ok, activity = %Activity{}} -> render(conn, "show.json", %{activity: activity, for: user})
    end
  end

  def fetch_conversation(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    id = String.to_integer(id)
    with context when is_binary(context) <- TwitterAPI.conversation_id_to_context(id),
         activities <- ActivityPub.fetch_activities_for_context(context)
    do
      render(conn, "timeline.json", %{activities: activities, for: user})
    else _e ->
      json(conn, [])
    end
  end

  #TODO: DRY the code

  def favorite(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    case find_activity(conn, id) do
      {:not_found, response} -> response
      {:ok, activity = %Activity{data: %{"object" => %{"id" => object_id}}}} ->
        object = Object.get_by_ap_id(object_id)
        case ActivityPub.like(user, object) do
          {:ok, _like, object = %Object{}} ->
            activity = update_data(activity, object)
            render(conn, "show.json", %{activity: activity, for: user})
        end
    end
  end

  def unfavorite(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    case find_activity(conn, id) do
      {:not_found, response} -> response
      {:ok, activity = %Activity{data: %{"object" => %{"id" => object_id}}}} ->
        object = Object.get_by_ap_id(object_id)
        case ActivityPub.unlike(user, object) do
          {:ok, object = %Object{}} ->
            activity = update_data(activity, object)
            render(conn, "show.json", %{activity: activity, for: user})
        end
    end
  end

  def retweet(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    case find_activity(conn, id) do
      {:not_found, response} -> response
      {:ok, activity = %Activity{data: %{"actor" => actor, "object" => %{"id" => object_id}}}} ->
        if actor == user.ap_id do
          conn
          |> put_status(:bad_request)
          |> render(ErrorView, "error.json", %{request_path: conn.request_path,
                                               message: "You cannot repeat your own status."})
        else
          object = Object.get_by_ap_id(object_id)
          case ActivityPub.announce(user, object) do
            {:ok, _announce, object = %Object{}} ->
              activity = update_data(activity, object)
              render(conn, "show.json", %{activity: activity, for: user})
          end
        end
    end
  end

  defp update_data(activity = %Activity{data: data}, %Object{data: object_data}) do
    new_data = Map.put(data, "object", object_data)
    %{activity | data: new_data}
  end

  defp find_activity(conn, id) do
    case Repo.get(Activity, id) do
      nil ->
        response = conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", %{request_path: conn.request_path,
                                             message: "No such status."})
        {:not_found, response}

      activity = %Activity{} -> {:ok, activity}
    end
  end
end
