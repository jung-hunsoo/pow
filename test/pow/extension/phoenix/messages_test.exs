defmodule Pow.Extension.Phoenix.MessagesTest do
  defmodule Phoenix.Messages do
    def a(_conn), do: "First"
    def b(_conn), do: "Second"
  end

  defmodule Messages do
    use Pow.Extension.Phoenix.Messages,
      extensions: [Pow.Extension.Phoenix.MessagesTest]

    def pow_a(_conn), do: "Overridden"
  end

  use ExUnit.Case
  doctest Pow.Extension.Phoenix.Messages

  test "can override messages" do
    assert Messages.pow_a(nil) == "Overridden"
    assert Messages.pow_b(nil) == "Second"
  end
end
