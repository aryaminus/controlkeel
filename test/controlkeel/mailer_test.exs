defmodule ControlKeel.MailerTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Mailer
  alias ControlKeel.Mailer.TestInbox

  setup do
    TestInbox.clear()
    :ok
  end

  describe "deliver_invitation/2 in :test mode" do
    test "captures the delivery into the inbox" do
      assert :ok = Mailer.deliver_invitation(%{email: "x@example.com"}, "raw-token-abc")

      assert {:invitation, payload, %DateTime{}} = TestInbox.find_by_email("x@example.com")
      assert payload.to == "x@example.com"
      assert payload.token == "raw-token-abc"
      assert payload.url == "/invitations/raw-token-abc"
    end

    test "all/0 returns deliveries newest first" do
      :ok = Mailer.deliver_invitation(%{email: "a@x"}, "ta")
      :ok = Mailer.deliver_invitation(%{email: "b@x"}, "tb")

      assert [{:invitation, %{to: "b@x"}, _}, {:invitation, %{to: "a@x"}, _}] = TestInbox.all()
    end

    test "find_by_email/1 returns nil when no match" do
      assert TestInbox.find_by_email("nobody@x") == nil
    end

    test "includes the invitation expiry when supplied" do
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(14 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      assert :ok =
               Mailer.deliver_invitation(%{email: "exp@x"}, "tok", expires_at: expires_at)

      assert {:invitation, payload, _} = TestInbox.find_by_email("exp@x")
      assert payload.expires_at == DateTime.to_iso8601(expires_at)
    end

    test "omits the expiry key when not supplied" do
      assert :ok = Mailer.deliver_invitation(%{email: "noexp@x"}, "tok")
      assert {:invitation, payload, _} = TestInbox.find_by_email("noexp@x")
      refute Map.has_key?(payload, :expires_at)
    end
  end

  describe "deliver_invitation/2 input validation" do
    test "rejects a recipient without :email" do
      assert {:error, :invalid_recipient} =
               Mailer.deliver_invitation(%{name: "no email here"}, "tok")
    end

    test "rejects non-binary token" do
      assert {:error, :invalid_recipient} =
               Mailer.deliver_invitation(%{email: "x@y"}, nil)
    end
  end

  describe "adapter switching" do
    test ":log mode returns :ok without touching the inbox" do
      previous = Application.get_env(:controlkeel, :mailer_adapter)
      Application.put_env(:controlkeel, :mailer_adapter, :log)
      on_exit(fn -> Application.put_env(:controlkeel, :mailer_adapter, previous) end)

      TestInbox.clear()
      assert :ok = Mailer.deliver_invitation(%{email: "log@x"}, "tok")
      assert TestInbox.all() == []
    end

    test "unknown adapter returns an error tuple" do
      previous = Application.get_env(:controlkeel, :mailer_adapter)
      Application.put_env(:controlkeel, :mailer_adapter, :bogus)
      on_exit(fn -> Application.put_env(:controlkeel, :mailer_adapter, previous) end)

      assert {:error, {:unsupported_mailer, :bogus}} =
               Mailer.deliver_invitation(%{email: "x@y"}, "tok")
    end
  end
end
