defmodule CodebattleWeb.ChatChannel do
  @moduledoc false
  use CodebattleWeb, :channel

  require Logger

  alias Codebattle.{Chat, Tournament, GameProcess, UsersActivityServer, GameProcess}
  alias Codebattle.GameProcess.FsmHelpers

  def join("chat:" <> chat_id, _payload, socket) do
    send(self(), :after_join)

    {server, id} = get_chat_server(chat_id)
    {:ok, users} = server.join_chat(id, socket.assigns.current_user)

    GameProcess.Server.update_playbook(
      chat_id,
      :join_chat,
      %{
        id: socket.assigns.current_user.id,
        name: socket.assigns.current_user.name
      }
    )

    msgs = server.get_msgs(chat_id)

    {:ok, %{users: users, messages: msgs}, socket}
  end

  def handle_info(:after_join, socket) do
    chat_id = get_chat_id(socket)
    {server, id} = get_chat_server(chat_id)
    users = server.get_users(id)
    broadcast_from!(socket, "user:joined", %{users: users})
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    chat_id = get_chat_id(socket)
    {server, id} = get_chat_server(chat_id)
    {:ok, users} = server.leave_chat(id, socket.assigns.current_user)

    GameProcess.Server.update_playbook(
      chat_id,
      :leave_chat,
      %{
        id: socket.assigns.current_user.id,
        name: socket.assigns.current_user.name
      }
    )

    broadcast_from!(socket, "user:left", %{users: users})
    {:noreply, socket}
  end

  def handle_in("new:message", payload, socket) do
    %{"message" => message} = payload
    user = socket.assigns.current_user
    chat_id = get_chat_id(socket)
    {server, id} = get_chat_server(chat_id)
    server.add_msg(id, user, message)

    UsersActivityServer.add_event(%{
      event: "new_message_game",
      user_id: user.id,
      data: %{
        game_id: chat_id
      }
    })

    GameProcess.Server.update_playbook(
      chat_id,
      :chat_message,
      %{
        id: user.id,
        name: user.name,
        message: message
      }
    )

    broadcast!(socket, "new:message", %{user: user.name, message: message})
    {:noreply, socket}
  end

  defp get_chat_id(socket) do
    "chat:" <> chat_id = socket.topic
    chat_id
  end

  defp get_chat_server(chat_id) do
    game_id = chat_id
    {:ok, fsm} = Codebattle.GameProcess.Server.get_fsm(game_id)

    if FsmHelpers.tournament?(fsm) do
      {Tournament.Server, FsmHelpers.get_tournament_id(fsm)}
    else
      {Chat.Server, chat_id}
    end
  end
end
