defmodule Pleroma.Web.TwitterAPI.UserController do
  use Pleroma.Web, :controller
  alias Ecto.Changeset
  alias Pleroma.{Repo, User, Misc}
  alias Pleroma.Web.ActivityPub.ActivityPub

  def verify_credentials(%{assigns: %{user: user}} = conn, _params) do
    render conn, "show.json", %{user: user, for: user}
  end

  def follow(%{assigns: %{user: follower}} = conn, params) do
    with {:ok, %User{} = followed} <- get_user(params),
         {:ok, follower} <- User.follow(follower, followed),
         {:ok, activity} <- ActivityPub.follow(follower, followed)
    do
      render conn, "show.json", %{user: followed, for: follower}
    else
      {:error, message} ->
        conn
        |> put_status(:not_found)
        |> render(Pleroma.Web.TwitterAPI.ErrorView, "error.json",
                  %{request_path: conn.request_path, message: message})
    end
  end

  def unfollow(%{assigns: %{user: follower}} = conn, params) do
    with { :ok, %User{} = unfollowed } <- get_user(params),
         { :ok, follower, follow_activity } <- User.unfollow(follower, unfollowed),
         { :ok, _activity } <- ActivityPub.insert(%{
               "type" => "Undo",
               "actor" => follower.ap_id,
               "object" => follow_activity.data["id"], # get latest Follow for these users
               "published" => Misc.make_date()
         })
    do
      render conn, "show.json", %{user: unfollowed, for: follower}
    else
      {:error, message} ->
        conn
        |> put_status(:not_found)
        |> render(Pleroma.Web.TwitterAPI.ErrorView, "error.json",
                  %{request_path: conn.request_path, message: message})
    end
  end

  def register(conn, params) do
    params = %{
      nickname: params["nickname"],
      name: params["fullname"],
      bio: params["bio"],
      email: params["email"],
      password: params["password"],
      password_confirmation: params["confirm"]
    }

    changeset = User.register_changeset(%User{}, params)

    with {:ok, user} <- Repo.insert(changeset) do
      render conn, "show.json", %{user: user}
    else
      {:error, changeset} ->
        errors = Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        conn
        |> put_status(:bad_request)
        |> render(Pleroma.Web.TwitterAPI.ErrorView, "error.json",
                  %{request_path: conn.request_path, message: errors})
    end
  end

  def update_avatar(%{assigns: %{user: user}} = conn, params) do
    {:ok, object} = ActivityPub.upload(params)
    change = Changeset.change(user, %{avatar: object.data})
    {:ok, user} = Repo.update(change)

    render conn, "show.json", %{user: user}
  end

  defp get_user(user \\ nil, params) do
    case params do
      %{"user_id" => user_id} ->
        case target = Repo.get(User, user_id) do
          nil ->
            {:error, "No user with such user_id"}
          _ ->
            {:ok, target}
        end
      %{"screen_name" => nickname} ->
        case target = Repo.get_by(User, nickname: nickname) do
          nil ->
            {:error, "No user with such screen_name"}
          _ ->
            {:ok, target}
        end
      _ ->
        if user do
          {:ok, user}
        else
          {:error, "You need to specify screen_name or user_id"}
        end
    end
  end
end
