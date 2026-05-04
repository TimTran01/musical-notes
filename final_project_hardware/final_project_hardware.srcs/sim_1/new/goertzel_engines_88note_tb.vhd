----------------------------------------------------------------------------------
-- Testbench: goertzel_engines_88note_tb
--
-- Description:
--   Sweeps all 88 piano-key bins through the three-bank Goertzel wrapper. Each
--   test resets the wrapper, launches all three banks, and drives one generated
--   128-sample pure-tone block into the target bank while the other two banks
--   receive zeros.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use std.env.all;

entity goertzel_engines_88note_tb is
end entity goertzel_engines_88note_tb;

architecture sim of goertzel_engines_88note_tb is

    constant CLK_PERIOD  : time := 10 ns;
    constant NOTE_COUNT  : natural := 88;
    constant BLOCK_SIZE  : natural := 128;
    constant SAMPLE_COUNT : natural := NOTE_COUNT * BLOCK_SIZE;
    constant SOURCE_DIR  : string := "";

    type sample_mem_t is array (0 to SAMPLE_COUNT - 1) of signed(23 downto 0);

    impure function load_samples(file_name : string) return sample_mem_t is
        file sample_file      : text open read_mode is file_name;
        variable memory       : sample_mem_t := (others => (others => '0'));
        variable current_line : line;
        variable sample_word  : std_logic_vector(23 downto 0);
        variable read_ok      : boolean;
        variable index        : natural := 0;
    begin
        while (not endfile(sample_file)) and (index < SAMPLE_COUNT) loop
            readline(sample_file, current_line);
            hread(current_line, sample_word, read_ok);

            assert read_ok
                report "goertzel_engines_88note_tb: invalid sample hex in " & file_name
                severity failure;

            memory(index) := signed(sample_word);
            index := index + 1;
        end loop;

        assert index = SAMPLE_COUNT
            report "goertzel_engines_88note_tb: " & file_name & " has the wrong sample count"
            severity failure;

        return memory;
    end function load_samples;

    signal sys_clk     : std_logic := '0';
    signal sys_rst     : std_logic := '1';
    signal RAM_DATA3   : signed(23 downto 0) := (others => '0');
    signal RAM_DATA12  : signed(23 downto 0) := (others => '0');
    signal RAM_DATA48  : signed(23 downto 0) := (others => '0');
    signal G_EN3       : std_logic := '0';
    signal G_EN12      : std_logic := '0';
    signal G_EN48      : std_logic := '0';
    signal RAM_ADDR3   : unsigned(11 downto 0);
    signal RAM_ADDR12  : unsigned(11 downto 0);
    signal RAM_ADDR48  : unsigned(11 downto 0);
    signal G_DONE3     : std_logic;
    signal G_DONE12    : std_logic;
    signal G_DONE48    : std_logic;
    signal NOTE_KEY    : unsigned(6 downto 0);
    signal NOTE_VALID  : std_logic;

    signal target_index : natural range 0 to NOTE_COUNT - 1 := 0;

    signal bank3_samples  : sample_mem_t := load_samples(SOURCE_DIR & "all88_bank3_samples.mem");
    signal bank12_samples : sample_mem_t := load_samples(SOURCE_DIR & "all88_bank12_samples.mem");
    signal bank48_samples : sample_mem_t := load_samples(SOURCE_DIR & "all88_bank48_samples.mem");

begin

    sys_clk <= not sys_clk after CLK_PERIOD / 2;

    dut : entity work.goertzel_engines_3bank
        generic map (
            BANK1_COEFF_FILE => SOURCE_DIR & "goertzel_bank1_coeff.mem",
            BANK2_COEFF_FILE => SOURCE_DIR & "goertzel_bank2_coeff.mem",
            BANK3_COEFF_FILE => SOURCE_DIR & "goertzel_bank3_coeff.mem"
        )
        port map (
            sys_clk     => sys_clk,
            sys_rst     => sys_rst,
            RAM_DATA3   => RAM_DATA3,
            RAM_DATA12  => RAM_DATA12,
            RAM_DATA48  => RAM_DATA48,
            G_EN3       => G_EN3,
            G_EN12      => G_EN12,
            G_EN48      => G_EN48,
            RAM_ADDR3   => RAM_ADDR3,
            RAM_ADDR12  => RAM_ADDR12,
            RAM_ADDR48  => RAM_ADDR48,
            G_DONE3     => G_DONE3,
            G_DONE12    => G_DONE12,
            G_DONE48    => G_DONE48,
            NOTE_KEY    => NOTE_KEY,
            NOTE_VALID  => NOTE_VALID
        );

    ram_model_proc : process (sys_clk)
        variable base_index : natural;
        variable addr3      : natural;
        variable addr12     : natural;
        variable addr48     : natural;
    begin
        if rising_edge(sys_clk) then
            base_index := target_index * BLOCK_SIZE;
            addr3 := to_integer(RAM_ADDR3);
            addr12 := to_integer(RAM_ADDR12);
            addr48 := to_integer(RAM_ADDR48);

            assert addr3 < BLOCK_SIZE
                report "goertzel_engines_88note_tb: Bank1/3 kHz read beyond block 0 after reset"
                severity failure;
            assert addr12 < BLOCK_SIZE
                report "goertzel_engines_88note_tb: Bank2/12 kHz read beyond block 0 after reset"
                severity failure;
            assert addr48 < BLOCK_SIZE
                report "goertzel_engines_88note_tb: Bank3/48 kHz read beyond block 0 after reset"
                severity failure;

            RAM_DATA3  <= bank3_samples(base_index + addr3);
            RAM_DATA12 <= bank12_samples(base_index + addr12);
            RAM_DATA48 <= bank48_samples(base_index + addr48);
        end if;
    end process ram_model_proc;

    stim_proc : process
        variable watchdog : natural;
    begin
        for note_index in 0 to NOTE_COUNT - 1 loop
            target_index <= note_index;
            sys_rst <= '1';
            G_EN3 <= '0';
            G_EN12 <= '0';
            G_EN48 <= '0';

            for reset_cycle in 0 to 4 loop
                wait until rising_edge(sys_clk);
            end loop;

            sys_rst <= '0';
            wait until rising_edge(sys_clk);

            G_EN3 <= '1';
            G_EN12 <= '1';
            G_EN48 <= '1';
            wait until rising_edge(sys_clk);
            G_EN3 <= '0';
            G_EN12 <= '0';
            G_EN48 <= '0';

            watchdog := 0;
            loop
                wait until rising_edge(sys_clk);
                wait for 1 ns;
                watchdog := watchdog + 1;

                assert watchdog < 50000
                    report "goertzel_engines_88note_tb: timeout waiting for NOTE_VALID"
                    severity failure;

                exit when NOTE_VALID = '1';
            end loop;

            assert NOTE_KEY >= to_unsigned(1, NOTE_KEY'length) and
                   NOTE_KEY <= to_unsigned(88, NOTE_KEY'length)
                report "goertzel_engines_88note_tb: NOTE_KEY outside workbook range"
                severity failure;

            report "ALL88_NOTE target=" &
                   integer'image(note_index + 1) &
                   " observed=" &
                   integer'image(to_integer(NOTE_KEY))
                   severity note;

            for gap_cycle in 0 to 4 loop
                wait until rising_edge(sys_clk);
            end loop;
        end loop;

        report "goertzel_engines_88note_tb completed successfully" severity note;
        finish;
    end process stim_proc;

end architecture sim;
