defmodule LuxpkgsWeb.ConfirmModal do
  @moduledoc """
  Confirmation dialog for destructive actions.

  The caller provides the description and the confirm button. When a form is
  given, the dialog body and confirm button are wrapped in that form so the
  confirm button submits normally.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :form, :any, default: nil
  attr :form_id, :string, default: nil
  attr :submit, :string, default: nil
  slot :inner_block, required: true
  slot :confirm, required: true

  def confirm_modal(assigns) do
    ~H"""
    <dialog
      id={@id}
      class="modal"
      phx-update="ignore"
      phx-hook="Dialog"
      aria-labelledby={"#{@id}-title"}
    >
      <div class="modal-box">
        <h3 id={"#{@id}-title"} class="text-lg font-bold text-base-content">
          {@title}
        </h3>

        <.form
          :if={@form}
          for={@form}
          id={@form_id}
          phx-submit={@submit}
          class="space-y-4"
        >
          <div class="py-2 text-sm text-base-content/80">
            {render_slot(@inner_block)}
          </div>
          <.actions id={@id}>{render_slot(@confirm)}</.actions>
        </.form>

        <div :if={!@form}>
          <div class="py-2 text-sm text-base-content/80">
            {render_slot(@inner_block)}
          </div>
          <.actions id={@id}>{render_slot(@confirm)}</.actions>
        </div>
      </div>

      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true

  defp actions(assigns) do
    ~H"""
    <div class="modal-action">
      <button type="button" class="btn btn-neutral mr-3" onclick={"#{@id}.close()"}>
        Cancel
      </button>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
