defmodule ArcanumWeb.FailureLog do
  @moduledoc "Logs expected failures without exposing submitted values or credentials."

  require Logger

  def log(operation, %Ecto.Changeset{} = changeset) do
    errors =
      Enum.map(changeset.errors, fn {field, {_message, opts}} ->
        {field, Keyword.get(opts, :validation) || Keyword.get(opts, :constraint)}
      end)

    Logger.warning("#{operation} failed: validation errors #{inspect(errors)}")
  end

  def log(operation, reason) when is_atom(reason) do
    Logger.warning("#{operation} failed: #{reason}")
  end

  def log(operation, _reason), do: Logger.warning("#{operation} failed: unexpected error")
end
