defmodule Pleroma.Web.Streamer do
  use GenServer
  require Logger
  import Plug.Conn

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def add_conn(user, conn) do
    GenServer.cast(__MODULE__, %{action: :add, user: user, conn: conn})
  end

  def stream(user, item) do
    GenServer.cast(__MODULE__, %{action: :stream, user: user, item: item})
  end

  def handle_cast(%{action: :stream, user: user, item: item}, users) do
    Logger.debug("Trying to push to #{user.nickname}")
    if conn = users[user.id] do
      Logger.debug("Pushing item to #{user.id}, #{user.nickname}")
      chunk(conn, "event: #{item.type}\ndata: #{item.payload}\n\n")
    end
    {:noreply, users}
  end

  def handle_cast(%{action: :add, user: user, conn: conn}, users) do
    conn = conn
    |> put_resp_header("content-type", "text/event-stream")
    |> send_chunked(200)

    users = Map.put(users, user.id, conn)
    Logger.debug("Got new conn for user #{user.id}, #{user.nickname}")
    {:noreply, users}
  end

  def handle_cast(m, state) do
    IO.inspect("Unknown: #{inspect(m)}, #{inspect(state)}")
    {:noreply, state}
  end
end
