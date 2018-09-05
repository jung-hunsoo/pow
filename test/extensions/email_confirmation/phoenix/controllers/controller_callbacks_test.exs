defmodule PowEmailConfirmation.Phoenix.ControllerCallbacksTest do
  use PowEmailConfirmation.TestWeb.Phoenix.ConnCase

  alias Pow.{Ecto.Schema.Password, Plug}
  alias PowEmailConfirmation.Test.Users.User

  @password "secret1234"

  describe "Pow.Phoenix.SessionController.create/2" do
    @valid_params %{"email" => "test@example.com", "password" => @password}

    test "when email unconfirmed ", %{conn: conn} do
      conn = post conn, Routes.pow_session_path(conn, :create, %{"user" => @valid_params})

      assert get_flash(conn, :error) == "You'll need to confirm your e-mail before you can sign in. An e-mail confirmation link has been sent to you."
      assert redirected_to(conn) == Routes.pow_session_path(conn, :new)

      refute Plug.Helpers.current_user(conn)

      assert_received {:mail_mock, mail}
      assert token = mail.user.email_confirmation_token
      refute mail.user.email_confirmed_at
      assert mail.html =~ "<a href=\"http://localhost/confirm-email/#{token}\">"
    end

    test "when email has been confirmed", %{conn: conn} do
      conn = post conn, Routes.pow_session_path(conn, :create, %{"user" => Map.put(@valid_params, "email", "confirmed@example.com")})

      assert get_flash(conn, :info) == "signed_in"
      assert redirected_to(conn) == "/"
    end
  end

  describe "Pow.Phoenix.RegistrationController.create/2" do
    @valid_params %{"user" => %{"email" => "test@example.com", "password" => @password, "confirm_password" => @password}}

    test "with valid params", %{conn: conn} do
      conn = post conn, Routes.pow_registration_path(conn, :create, @valid_params)

      assert get_flash(conn, :error) == "You'll need to confirm your e-mail before you can sign in. An e-mail confirmation link has been sent to you."
      assert redirected_to(conn) == Routes.pow_session_path(conn, :new)

      refute Plug.Helpers.current_user(conn)

      assert_received {:mail_mock, mail}
      assert token = mail.user.email_confirmation_token
      refute mail.user.email_confirmed_at
      assert mail.html =~ "<a href=\"http://localhost/confirm-email/#{token}\">"
    end
  end

  describe "Pow.Phoenix.RegistrationController.update/2" do
    @token               "token"
    @user                %User{id: 1, email: "test@example.com", password_hash: Password.pbkdf2_hash(@password), email_confirmation_token: @token}
    @params              %{"user" => %{"email" => "test@example.com", "current_password" => @password}}
    @change_email_params %{"user" => %{"email" => "new@example.com", "current_password" => @password}}

    setup %{conn: conn} do
      user = Ecto.put_meta(@user, state: :loaded)
      conn = Plug.Helpers.assign_current_user(conn, user, [])

      {:ok, conn: conn}
    end

    test "when email changes", %{conn: conn} do
      conn = put conn, Routes.pow_registration_path(conn, :update, @change_email_params)
      assert %{id: 1, email_confirmation_token: new_token} = Plug.Helpers.current_user(conn)

      assert get_flash(conn, :info) == "Your account has been updated."
      assert new_token != @token

      assert_received {:mail_mock, mail}
      assert mail.subject == "Confirm your email address"
      assert mail.text =~ "\nhttp://localhost/confirm-email/#{new_token}\n"
      assert mail.html =~ "<a href=\"http://localhost/confirm-email/#{new_token}\">"
    end

    test "when email hasn't changed", %{conn: conn} do
      conn = put conn, Routes.pow_registration_path(conn, :update, @params)

      assert get_flash(conn, :info) == "Your account has been updated."
      assert %{id: 1, email_confirmation_token: @token} = Plug.Helpers.current_user(conn)

      refute_received {:mail_mock, _mail}
    end
  end
end
