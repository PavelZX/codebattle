defmodule CodebattleWeb.ChatChannel do
  @moduledoc false
  use CodebattleWeb, :channel

  require Logger

  alias Codebattle.{Chat, UsersActivityServer, GameProcess}
  alias Codebattle.GameProcess.FsmHelpers

  def get_chat_server(chat_id) do
    game_id = chat_id
    {:ok, fsm} = Codebattle.GameProcess.Server.get_fsm(game_id)
    if FsmHelpers.tournament?(fsm) do
      Codebattle.Tournament.Server
    else
      Chat.Server
    end
  end

  def join("chat:" <> chat_id, _payload, socket) do
    send(self(), :after_join)

    server = get_chat_server(chat_id)
    chat =
    {:ok, users} = Chat.Server.join_chat(chat_id, socket.assigns.current_user)

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
    server = get_chat_server(chat_id)
    users = Chat.Server.get_users(chat_id)
    broadcast_from!(socket, "user:joined", %{users: users})
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    chat_id = get_chat_id(socket)
    #server = get_chat_server(chat_id)
    {:ok, users} = Chat.Server.leave_chat(chat_id, socket.assigns.current_user)

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
    name = get_user_name(user)
    chat_id = get_chat_id(socket)
    server = get_chat_server(chat_id)
    server.add_msg(chat_id, name, message)

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
        name: name,
        message: message
      }
    )

    broadcast!(socket, "new:message", %{user: name, message: message})
    {:noreply, socket}
  end

  defp get_user_name(%{is_bot: true, name: name}), do: "#{name} (bot)"
  defp get_user_name(%{name: name}), do: name

  defp get_chat_id(socket) do
    "chat:" <> chat_id = socket.topic
    chat_id
  end
end
