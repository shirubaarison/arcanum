defmodule ArcanumWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use ArcanumWeb, :html

  embed_templates "error_html/*"

  def render("404.html", assigns), do: apply(__MODULE__, :"404", [assigns])

  # Other errors render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
