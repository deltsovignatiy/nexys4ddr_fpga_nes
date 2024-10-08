import time
import serial, serial.tools.list_ports
from pynput import keyboard
import sys


class RomParserNES:
    FLAGS6_HW_MIRRORING_POS = 0
    FLAGS6_MIRRORING_MASK = 0x01
    FLAGS6_PRG_RAM_PRESENT_POS = 1
    FLAGS6_PRG_RAM_PRESENT_MASK = 0x02
    FLAGS6_ALT_NAMETABLE_LAYOUT_POS = 3
    FLAGS6_ALT_NAMETABLE_LAYOUT_MASK = 0x08
    FLAGS6_MAPPER_NUMBER_POS = 4
    FLAGS6_MAPPER_NUMBER_MASK = 0xF0

    flags6_hw_mirroring_map = {0: "horizontal", 1: "vertical"}
    flags6_mapper_map = {0: "NROM", 1: "MMC1", 2: "UxROM", 3: "CNROM", 4: "MMC3", 7: "AxROM"}

    def __init__(self, nes):
        self._input_name = nes
        print(self._input_name)
        self._nes_file_name = nes.split("/")[-1].replace(".", "_", 1)
        self._nes_file = open(nes, 'rb')
        self._nes_data_bytes = bytearray(self._nes_file.read())
        self._nes_file.close()
        self._nes_data_size = len(self._nes_data_bytes)
        self._nes_const = self._nes_data_bytes[0:3]
        self._size_cpu_rom = self._nes_data_bytes[4]
        self._size_ppu_vrom = self._nes_data_bytes[5]
        self._flags6 = self._nes_data_bytes[6]
        _hw_mirroring = (self._flags6 & self.FLAGS6_MIRRORING_MASK) >> self.FLAGS6_HW_MIRRORING_POS
        self._hw_mirroring = self.flags6_hw_mirroring_map[_hw_mirroring]
        self._prg_ram = (self._flags6 & self.FLAGS6_PRG_RAM_PRESENT_MASK) >> self.FLAGS6_PRG_RAM_PRESENT_POS
        self._alt_nametable_layout = ((self._flags6 & self.FLAGS6_ALT_NAMETABLE_LAYOUT_MASK) >>
                                      self.FLAGS6_ALT_NAMETABLE_LAYOUT_POS)
        _mapper = (self._flags6 & self.FLAGS6_MAPPER_NUMBER_MASK) >> self.FLAGS6_MAPPER_NUMBER_POS
        self._mapper = self.flags6_mapper_map[_mapper]
        print("Number of PRG banks of 16384 bytes each is {}".format(self._size_cpu_rom))
        self._create_cpu_rom_init_txt_file()
        print("Number of CHR banks of 8192 bytes each is {}".format(self._size_ppu_vrom))
        if self._size_ppu_vrom:
            self._create_ppu_vrom_init_txt_file()
        else:
            print("Cartridge is using CHR RAM instead of CHR ROM")
        print("Hardware mirroring is {}".format(self._hw_mirroring))
        if self._alt_nametable_layout:
            print("Alternate NameTable layout is used!")
        if self._prg_ram:
            print("Cartridge contains PRG RAM!")
        print("Mapper is {}".format(self._mapper))
        print("Finished!")

    @staticmethod
    def _hex_output_writer(data, file):
        for i, hex_ in enumerate(data):
            s = hex_[2:]
            s = ("0" + s) if (len(s) == 1) else s
            s += " "
            file.write(s)
            if i % 16 == 15:
                file.write("\n")

    def _create_ppu_vrom_init_txt_file(self):
        vrom_file = open(self._nes_file_name + "_ppu_vrom.txt", "w")
        vrom_edge = 8192 * self._size_ppu_vrom
        vrom_bytes = self._nes_data_bytes[-vrom_edge:]
        vrom_data = []
        for _byte in vrom_bytes:
            vrom_data.append(hex(_byte))
        vrom_size = len(vrom_bytes)
        print("PPU CHR VROM size = {}".format(vrom_size))
        self._hex_output_writer(vrom_data, vrom_file)
        vrom_file.close()

    def _create_cpu_rom_init_txt_file(self):
        rom_file = open(self._nes_file_name + "_cpu_rom.txt", "w")
        rom_edge = 16384 * self._size_cpu_rom
        rom_bytes = self._nes_data_bytes[16:rom_edge+16]
        rom_data = []
        for _byte in rom_bytes:
            rom_data.append(hex(_byte))
        rom_size = len(rom_bytes)
        if rom_size == 16384:
            for _byte in rom_bytes:
                rom_data.append(hex(_byte))
        print("CPU PRG ROM size = {}".format(rom_size))
        self._hex_output_writer(rom_data, rom_file)
        rom_file.close()


class APUMixerLUT:
    BASE_WIDTH = 15
    BASE_VALUE = 1 << BASE_WIDTH

    def __init__(self):
        self._pulse_table = [round(self._pulse_equation(n) if (n > 0) else 0.0) for n in range(0, 31)]
        self._tnd_table = [round(self._tnd_equation(n) if (n > 0) else 0.0) for n in range(0, 203)]
        align = "            "
        for index, val in enumerate(self._pulse_table):
            print(align + "5'h{}:   pulse_lut_output_r = {}'d{};".format(format(index, '02X'), self.BASE_WIDTH, val))
        print("\n")
        for index, val in enumerate(self._tnd_table):
            print(align + "8'h{}:   tnd_lut_output_r   = {}'d{};".format(format(index, '02X'), self.BASE_WIDTH, val))

    def _pulse_equation(self, n):
        return 95.52 * self.BASE_VALUE / (8128.0 / n + 100)

    def _tnd_equation(self, n):
        return 163.67 * self.BASE_VALUE / (24329.0 / n + 100)


def list_serial_ports():
    for port in list(serial.tools.list_ports.comports()):
        print(f"Устройство:    {port.device}")
        print(f"Описание:      {port.description}")
        print(f"Производитель: {port.manufacturer}\n")


class InputNES:
    A_BUTTON_POS = 0
    B_BUTTON_POS = 1
    SELECT_BUTTON_POS = 2
    START_BUTTON_POS = 3
    UP_BUTTON_POS = 4
    DOWN_BUTTON_POS = 5
    LEFT_BUTTON_POS = 6
    RIGHT_BUTTON_POS = 7

    def __init__(self, port):
        self._key_pressed = [0] * 8
        try:
            # sudo chmod 777 port
            self.ser = serial.Serial(port=port, baudrate=115200, parity=serial.PARITY_NONE,
                                     stopbits=serial.STOPBITS_ONE, bytesize=serial.EIGHTBITS)
            if not self.ser.is_open:
                quit()
        finally:
            pass
        listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release)
        listener.start()
        while True:
            try:
                data = self._get_keyboard_input_byte()
                self.ser.write(data)
                time.sleep(0.016)
            finally:
                pass

    def _get_keyboard_input_byte(self):
        _keyboard_input = 0
        val = self._key_pressed[self.RIGHT_BUTTON_POS] and not self._key_pressed[self.LEFT_BUTTON_POS]
        _keyboard_input |= (val << self.RIGHT_BUTTON_POS)
        val = self._key_pressed[self.LEFT_BUTTON_POS] and not self._key_pressed[self.RIGHT_BUTTON_POS]
        _keyboard_input |= (val << self.LEFT_BUTTON_POS)
        val = self._key_pressed[self.DOWN_BUTTON_POS] and not self._key_pressed[self.UP_BUTTON_POS]
        _keyboard_input |= (val << self.DOWN_BUTTON_POS)
        val = self._key_pressed[self.UP_BUTTON_POS] and not self._key_pressed[self.DOWN_BUTTON_POS]
        _keyboard_input |= (val << self.UP_BUTTON_POS)
        _key_pressed_slice = self._key_pressed[0:4]
        for index, val in enumerate(_key_pressed_slice):
            _keyboard_input |= (val << index)
        return _keyboard_input.to_bytes(1, "big")

    def _on_press(self, key):
        if key == keyboard.Key.right or (hasattr(key, 'char') and key.char == '6'):
            self._key_pressed[self.RIGHT_BUTTON_POS] = 1
        if key == keyboard.Key.left or (hasattr(key, 'char') and key.char == '4'):
            self._key_pressed[self.LEFT_BUTTON_POS] = 1
        if key == keyboard.Key.down or (hasattr(key, 'char') and key.char == '2'):
            self._key_pressed[self.DOWN_BUTTON_POS] = 1
        if key == keyboard.Key.up or (hasattr(key, 'char') and key.char == '8'):
            self._key_pressed[self.UP_BUTTON_POS] = 1
        if key == keyboard.Key.enter:  # start
            self._key_pressed[self.START_BUTTON_POS] = 1
        if key == keyboard.Key.space:  # select
            self._key_pressed[self.SELECT_BUTTON_POS] = 1
        if key == keyboard.KeyCode.from_char('w'):  # B
            self._key_pressed[self.B_BUTTON_POS] = 1
        if key == keyboard.KeyCode.from_char('q'):  # A
            self._key_pressed[self.A_BUTTON_POS] = 1
        # print('Key %s pressed' % key)

    def _on_release(self, key):
        if key == keyboard.Key.right or (hasattr(key, 'char') and key.char == '6'):
            self._key_pressed[self.RIGHT_BUTTON_POS] = 0
        if key == keyboard.Key.left or (hasattr(key, 'char') and key.char == '4'):
            self._key_pressed[self.LEFT_BUTTON_POS] = 0
        if key == keyboard.Key.down or (hasattr(key, 'char') and key.char == '2'):
            self._key_pressed[self.DOWN_BUTTON_POS] = 0
        if key == keyboard.Key.up or (hasattr(key, 'char') and key.char == '8'):
            self._key_pressed[self.UP_BUTTON_POS] = 0
        if key == keyboard.Key.enter:  # start
            self._key_pressed[self.START_BUTTON_POS] = 0
        if key == keyboard.Key.space:  # select
            self._key_pressed[self.SELECT_BUTTON_POS] = 0
        if key == keyboard.KeyCode.from_char('w'):  # B
            self._key_pressed[self.B_BUTTON_POS] = 0
        if key == keyboard.KeyCode.from_char('q'):  # A
            self._key_pressed[self.A_BUTTON_POS] = 0
        # print('Key %s released' % key)


# Press the green button in the gutter to run the script.
if __name__ == '__main__':
    if len(sys.argv) > 1:
        InputNES(sys.argv[1])
    else:
        list_serial_ports()
    pass
