defmodule Pleroma.Web.TwitterAPI.UserController do
  use Pleroma.Web, :controller
  alias Ecto.Changeset
  alias Pleroma.{Activity, Object, Repo, User, Misc}
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.TwitterAPI.ErrorView

  def verify_credentials(%{assigns: %{user: user}} = conn, _params) do
    render conn, "show.json", %{user: user, for: user}
  end

  def follow(%{assigns: %{user: follower}} = conn, params) do
    case find_user(conn, params) do
      {:ok, followed = %User{}} ->
        case User.follow(follower, followed) do
          {:ok, follower = %User{}} ->
            {:ok, _activity} = ActivityPub.follow(follower, followed)
            render conn, "show.json", %{user: followed, for: follower}
          {:error, message} ->
            conn
            |> put_status(:bad_request)
            |> render(ErrorView, "error.json", %{request_path: conn.request_path, message: message})
        end
      {:error, response} -> response
    end
  end

  def unfollow(%{assigns: %{user: follower}} = conn, params) do
    case find_user(conn, params) do
      {:ok, unfollowed = %User{}} ->
        case User.unfollow(follower, unfollowed) do
          {:ok, follower = %User{ap_id: ap_id}, %Activity{data: %{"id" => id}}} ->
            {:ok, _activity} = ActivityPub.insert(%{
              "type" => "Undo",
              "actor" => ap_id,
              "object" => id, # get latest Follow for these users
              "published" => Misc.make_date()
            })
            render conn, "show.json", %{user: unfollowed, for: follower}
          {:error, message} ->
            conn
            |> put_status(:bad_request)
            |> render(ErrorView, "error.json", %{request_path: conn.request_path, message: message})
        end
      {:error, response} -> response
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
        |> render(ErrorView, "error.json",
                  %{request_path: conn.request_path, message: errors})
    end
  end

  def update_avatar(%{assigns: %{user: user}} = conn, params) do
    {:ok, %Object{data: data}} = ActivityPub.upload(params)
    change = Changeset.change(user, %{avatar: data})
    {:ok, user} = Repo.update(change)
    render conn, "show.json", %{user: user}
  end

  def find_user(%{assigns: %{user: user}} = conn, params) do
    case User.get_by_params(user, params) do
      {:ok, user = %User{}} -> {:ok, user}
      {status, message} ->
        response = conn
        |> put_status(status)
        |> render(ErrorView, "error.json", %{request_path: conn.request_path, message: message})
        {:error, response}
    end
  end
end
