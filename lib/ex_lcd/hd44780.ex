defmodule ExLCD.HD44780 do
  @moduledoc """
  **ExLCD.HD44780** is the display driver module for Hitachi
  HD44780 type parallel LCD display controller managed display modules.

  ## Hitachi HD44780 Style Controller (including Sitronix ST7066)

  The HD44780 is the most ubiquitous character matrix display controller
  but not the only one. It supports a number of standard operations like
  moving the cursor, displaying characters and scrolling. It is an 8-bit
  parallel interface which can operate in 4-bit mode by sending 2 4-bit
  nibbles to make one 8-bit byte.

  It supports 208 characters which are compatible with UNICODE single byte
  latin characters. The controller character ROM includes a number of non-
  standard character glyphs which this driver maps to their multi-byte
  UNICODE equivilents automatically. See the character map in this file for
  details. There are also 8 user definable character bitmaps mapped to
  characters byte codes 0-7.

  ## Configuration

  The start/1 function expects to receive a map of configuration settings
  for the display and it's hardware interface. The configuration map is
  passed by your application to ExLCD.start_link/1 and then on to this
  driver module. Please see ExLCD for details. The following keys are
  used by this driver to operate the display:

  * *Key*     -> **Type(O|R)**  -> *Description*
  * rs        -> integer(R) -> The GPIO pin ID for the RS signal
  * en        -> integer(R) -> The GPIO pin ID for the EN signal
  * d0        -> integer(O) -> The GPIO pin ID for the d0 signal
  * d1        -> integer(O) -> The GPIO pin ID for the d1 signal
  * d2        -> integer(O) -> The GPIO pin ID for the d2 signal
  * d3        -> integer(O) -> The GPIO pin ID for the d3 signal
  * d4        -> integer(R) -> The GPIO pin ID for the d4 signal
  * d5        -> integer(R) -> The GPIO pin ID for the d5 signal
  * d6        -> integer(R) -> The GPIO pin ID for the d6 signal
  * d7        -> integer(R) -> The GPIO pin ID for the d7 signal
  * rows      -> integer(R) -> The number of display rows or lines
  * cols      -> integer(R) -> The number of display columns
  * font_5x10 -> boolean(O) -> Font: true: 5x10, false: 5x8 (default)

  O - optional
  R - required

  Example:

  ```elixir
    config :MyApp, hd44780: %{
      rs: 1,
      en: 2,
      d4: 3,
      d5: 4,
      d6: 5,
      d7: 6,
      rows: 2,
      cols: 20
    }
  ```

  ## More Information

  For more information about your display and its capabilities here are
  a few resources to help you get the most of it:

  * Hitachi HD44780 Datasheet
  * Wikipedia Entry for HD44780
  * ExLCD
  * Raspberry Pi Example Application with nerves
  """

  use Bitwise
  use ExLCD.Driver
  use ExLCD.IO

  @low    0
  @high   1

  # Function set flags
  @mode_4bit  0x01
  @mode_8bit  0x00
  @font_5x8   0x00
  @font_5x10  0x04
  @lines_1    0x00
  @lines_2    0x08

  # Command flags
  @cmd_clear        0x01
  @cmd_home         0x02
  @cmd_entrymodeset 0x04
  @cmd_dispcontrol  0x08
  @cmd_cursorshift  0x10
  @cmd_functionset  0x20
  @cmd_setcgramaddr 0x40
  @cmd_setddramaddr 0x80

  # Entry mode flags
  @entry_left       0x02
  @entry_increment  0x01

  # Display control flags
  @ctl_display      0x04
  @ctl_cursor       0x02
  @ctl_blink        0x01

  # Shift flags
  @shift_display    0x08
  @shift_right      0x04

  @pins_4bit [:rs, :en, :d4, :d5, :d6, :d7]
  @pins_8bit [:d0, :d1, :d2, :d3]

  # -------------------------------------------------------------------
  # CharDisplay.Driver Behaviour
  #
  @doc false
  def start(config) do
    init(config)
  end

  @doc false
  def stop(display) do
    {:ok, display} = command(display, {:display, :off})
    [ :rs_pid, :en_pid,
      :d0_pid, :d1_pid, :d2_pid, :d3_pid,
      :d4_pid, :d5_pid, :d6_pid, :d7_pid ]
    |>  Enum.filter(fn x -> not is_nil(display[x]) end)
    |>  Enum.each(fn x -> @gpio.release(display[x]) end)
    :ok
  end

  @doc false
  def execute do
    &command/2
  end

  # ------------------------------------------------------------------
  # Initialization
  #

  defp init(config) do
    # validate and unpack the config
    config |> validate_config!()

    bits = case config[:d0] do
      nil  ->  @mode_4bit
      _    ->  @mode_8bit
    end

    lines = case config.rows do
      1 ->  @lines_1
      _ ->  @lines_2
    end

    font = case config[:font_5x10] do
      true  ->  @font_5x10
      _     ->  @font_5x8
    end

    pins = case bits do
      @mode_8bit  ->  @pins_4bit ++ @pins_8bit
      _           ->  @pins_4bit
    end

    starting_function_state = @cmd_functionset ||| bits ||| font ||| lines

    display = Map.merge(config, %{
      function_set: starting_function_state,
      display_control: @cmd_dispcontrol,
      entry_mode: @cmd_entrymodeset,
      shift_control: @cmd_cursorshift
    })

    display
    |>  reserve_gpio_pins(pins)
    |>  rs(@low)
    |>  en(@low)
    |>  poi(bits)
    |>  set_feature(:function_set)
    |>  clear()
  end

  # setup GPIO output pins, add the pids to the config and return
  defp reserve_gpio_pins(config, pins) do
    config
    |>  Map.take(pins)
    |>  Enum.map(fn {k, v} -> {String.to_atom("#{k}_pid"), start_pin(v, :output)} end)
    |>  Map.new()
    |>  Map.merge(config)
  end

  # start ElixirALE.GPIO GenServer to manage a GPIO pin and return the pid
  defp start_pin(pin, direction) do
    with {:ok, pid} <- @gpio.start_link(pin, direction), do: pid
  end

  # Software Power On Init (POI) for 4bit operation of HD44780 controller.
  # Since the display is initialized more than 50mS after > 4.7V on due to
  # OS/BEAM/App boot time this isn't strictly necessary but let's be
  # safe and do it anyway.
  defp poi(state, @mode_4bit) do
    state
    |>  write_4_bits(0x03)
    |>  write_4_bits(0x03)
    |>  write_4_bits(0x03)
    |>  write_4_bits(0x02)
  end

  # POI for 8 bit mode
  defp poi(state, @mode_8bit) do
    state
    |>  set_feature(:function_set)
    |>  set_feature(:function_set)
    |>  set_feature(:function_set)
  end

  defp validate_config!(config) do
    config
  end

  # -------------------------------------------------------------------
  # ExLCD API callback
  #

  defp command(display, {:clear, _params}) do
    clear(display)
    {:ok, display}
  end

  defp command(display, {:home, _params}) do
    home(display)
    {:ok, display}
  end

  # translate string to charlist
  defp command(display, {:print, content}) do
    characters = String.to_charlist(content)
    command(display, {:write, characters})
  end

  defp command(display, {:write, content}) do
    content
    |>  Enum.each(fn(x) -> write_a_byte(display, x, @high) end)
    {:ok, display}
  end

  defp command(display, {:set_cursor, {row, col}}) do
    {:ok, set_cursor(display, {row, col})}
  end
  defp command(display, {:cursor, :off}) do
    {:ok, disable_feature_flag(display, :display_control, @ctl_cursor)}
  end
  defp command(display, {:cursor, :on}) do
    {:ok, enable_feature_flag(display, :display_control, @ctl_cursor)}
  end
  defp command(display, {:blink, :off}) do
    {:ok, disable_feature_flag(display, :display_control, @ctl_blink)}
  end
  defp command(display, {:blink, :on}) do
    {:ok, enable_feature_flag(display, :display_control, @ctl_blink)}
  end
  defp command(display, {:display, :off}) do
    {:ok, disable_feature_flag(display, :display_control, @ctl_display)}
  end
  defp command(display, {:display, :on}) do
    {:ok, enable_feature_flag(display, :display_control, @ctl_display)}
  end
  defp command(display, {:autoscroll, :off}) do
    {:ok, disable_feature_flag(display, :entry_mode, @entry_increment)}
  end
  defp command(display, {:autoscroll, :on}) do
    {:ok, enable_feature_flag(display, :entry_mode, @entry_increment)}
  end
  defp command(display, {:rtl_text, :on}) do
    {:ok, disable_feature_flag(display, :entry_mode, @entry_left)}
  end
  defp command(display, {:ltr_text, :on}) do
    {:ok, enable_feature_flag(display, :entry_mode, @entry_left)}
  end

  # Scroll the entire display left (-) or right (+)
  defp command(display, {:scroll, 0}), do: {:ok, display}
  defp command(display, {:scroll, cols}) when cols < 0 do
    write_a_byte(display, @cmd_cursorshift ||| @shift_display)
    command(display, {:scroll, cols + 1})
  end
  defp command(display, {:scroll, cols}) do
    write_a_byte(display, @cmd_cursorshift ||| @shift_display ||| @shift_right)
    command(display, {:scroll, cols - 1})
  end

  # Scroll(move) cursor right
  defp command(display, {:right, 0}), do: {:ok, display}
  defp command(display, {:right, cols}) do
    write_a_byte(display, @cmd_cursorshift ||| @shift_right)
    command(display, {:right, cols - 1})
  end

  # Scroll(move) cursor left
  defp command(display, {:left, 0}), do: {:ok, display}
  defp command(display, {:left, cols}) do
    write_a_byte(display, @cmd_cursorshift)
    command(display, {:left, cols - 1})
  end

  # Program custom character to CGRAM
  defp command(display, {:char, idx, bitmap}) when idx in 0..7 and length(bitmap) === 8 do
    write_a_byte(display, @cmd_setcgramaddr ||| idx)
    for line <- bitmap do
      write_a_byte(display, line, @high)
    end
    {:ok, display}
  end

  # All other commands are unsupported
  defp command(display, _), do: {:unsupported, display}

  # -------------------------------------------------------------------
  # Low-level device and utility functions
  #

  defp clear(display) do
    display
    |>  write_a_byte(@cmd_clear)
    |>  delay(3_000)
  end

  defp home(display) do
    display
    |>  write_a_byte(@cmd_home)
    |>  delay(3_000)
  end

  # DDRAM is organized as two 40 byte rows. In a 2x display the first row
  # maps to address 0x00 - 0x27 and the second row maps to 0x40 - 0x67
  # in a 4x display rows 0 & 2 are mapped to the first row of DDRAM and
  # rows 1 & 3 map to the second row of DDRAM. This means that the rows
  # are not contiguous in memory.
  #
  # row_offsets/1 determines the starting DDRAM address of each display row
  # and returns a map for up to 4 rows.
  defp row_offsets(cols) do
    %{ 0 => 0x00, 1 => 0x40, 2 => 0x00 + cols, 3 => 0x40 + cols }
  end

  # Set the DDRAM address corresponding to the {row,col} position
  defp set_cursor(display, {row, col}) do
    col = min(col, display[:cols] - 1)
    row = min(row, display[:rows] - 1)
    %{^row => offset} = row_offsets(display[:cols])
    write_a_byte(display, @cmd_setddramaddr ||| (col + offset))
  end

  # Switch a register flag bit OFF(0). Return the updated state.
  defp disable_feature_flag(state, feature, flag) do
    %{state | feature => (state[feature] &&& ~~~flag)}
    |>  set_feature(feature)
  end

  # Switch a register flag bit ON(1). Return the updated state.
  defp enable_feature_flag(state, feature, flag) do
    %{state | feature => (state[feature] ||| flag)}
    |>  set_feature(feature)
  end

  # Write a feature register to the controller and return the state.
  defp set_feature(display, feature) do
    display |> write_a_byte(display[feature])
  end

  # Write a byte to the device
  defp write_a_byte(display, byte_to_write, rs_value \\ @low) do
    display |> rs(rs_value) |> delay(1_000)

    case display[:d0] do
      nil -> display
             |>  write_4_bits(byte_to_write >>> 4)
             |>  write_4_bits(byte_to_write)
      _   -> display
             |>  write_8_bits(byte_to_write)
    end
  end

  # Write 8 parallel bits to the device
  defp write_8_bits(display, bits) do
    @gpio.write(display.d0_pid, bits &&& 0x01)
    @gpio.write(display.d1_pid, bits >>> 1 &&& 0x01)
    @gpio.write(display.d2_pid, bits >>> 2 &&& 0x01)
    @gpio.write(display.d3_pid, bits >>> 3 &&& 0x01)
    @gpio.write(display.d4_pid, bits >>> 4 &&& 0x01)
    @gpio.write(display.d5_pid, bits >>> 5 &&& 0x01)
    @gpio.write(display.d6_pid, bits >>> 6 &&& 0x01)
    @gpio.write(display.d7_pid, bits >>> 7 &&& 0x01)
    pulse_en(display)
  end

  # Write 4 parallel bits to the device
  defp write_4_bits(display, bits) do
    @gpio.write(display.d4_pid, bits &&& 0x01)
    @gpio.write(display.d5_pid, bits >>> 1 &&& 0x01)
    @gpio.write(display.d6_pid, bits >>> 2 &&& 0x01)
    @gpio.write(display.d7_pid, bits >>> 3 &&& 0x01)
    pulse_en(display)
  end

  defp rs(display, value) do
    @gpio.write(display[:rs_pid], value)
    display
  end

  defp en(display, value) do
    @gpio.write(display[:en_pid], value)
    display
  end

  defp pulse_en(display) do
    display
    |>  en(@low)
    |>  en(@high)
    |>  en(@low)
  end

  def delay(display, microseconds) do
    # Unfortunately, BEAM does not provides microsecond precision
    # And if we need waiting, we MUST wait
    ms = max(round(microseconds / 1000), 1)
    Process.sleep(ms)
    display
  end
end
