use Mix.Config

# Sample HD44780 configuration for a 2x20 display connected to
# my Raspberry Pi0W. The 4 bit interface requires 6 GPIO pins
# which are managed by the driver:
#
config :ex_lcd, lcd: %{
  rs: 25,
  en: 24,
  d4: 23,
  d5: 22,
  d6: 18,
  d7: 17,
  rows: 2,
  cols: 20,
  font_5x10: false
}
