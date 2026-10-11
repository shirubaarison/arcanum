defmodule Arcanum.Accounts.ActivationTest do
  use Arcanum.DataCase, async: true

  import Arcanum.AccountsFixtures
  alias Arcanum.Accounts

  setup do
    user = unconfirmed_user_fixture()
    {token, _} = generate_user_magic_link_token(user)
    %{user: user, token: token}
  end

  test "requires a valid password and matching confirmation without consuming the token", %{
    user: user,
    token: token
  } do
    for attrs <- [
          %{},
          %{password: "short", password_confirmation: "short"},
          %{password: valid_user_password()},
          %{password: valid_user_password(), password_confirmation: "different"}
        ] do
      assert {:error, %Ecto.Changeset{}} = Accounts.activate_user_by_magic_link(token, attrs)
      refute Accounts.get_user!(user.id).confirmed_at
      refute Accounts.get_user!(user.id).hashed_password
      assert Accounts.get_user_by_magic_link_token(token)
    end
  end

  test "activation hashes the password, confirms the account and invalidates old tokens", %{
    user: user,
    token: token
  } do
    session_token = Accounts.generate_user_session_token(user)

    assert {:ok, {activated, _}} =
             Accounts.activate_user_by_magic_link(
               token,
               %{password: valid_user_password(), password_confirmation: valid_user_password()}
             )

    assert activated.confirmed_at
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    refute Accounts.get_user_by_session_token(session_token)
    refute Accounts.get_user_by_magic_link_token(token)

    assert {:error, :not_found} =
             Accounts.activate_user_by_magic_link(
               token,
               %{password: valid_user_password(), password_confirmation: valid_user_password()}
             )
  end

  test "invalid links cannot activate an account" do
    assert {:error, :not_found} = Accounts.activate_user_by_magic_link("invalid", %{})
  end

  test "confirmed accounts cannot use activation to reset their password" do
    user = user_fixture() |> set_password()
    {token, _} = generate_user_magic_link_token(user)

    assert {:error, :not_found} =
             Accounts.activate_user_by_magic_link(
               token,
               %{
                 password: "another valid password",
                 password_confirmation: "another valid password"
               }
             )

    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
  end
end
