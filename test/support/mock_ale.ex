#
# Stub out elixir_ale for testing
#
defmodule ElixirALE.GPIO do
  @moduledoc false

  def start_link(pin, _pin_direction \\ :foo, _opts \\ []) do
    {:ok, pin}
  end

  def write(pin, value) do
    MockHD44780.write(pin, value)
    :ok
  end

  def release(_pin), do: :ok
end
