defmodule LuxpkgsWeb.AdminLive.Dashboard do
  use LuxpkgsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} current_admin={@current_admin}>
    </Layouts.admin>
    """
  end
end
