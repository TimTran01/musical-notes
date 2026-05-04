----------------------------------------------------------------------------------
-- Testbench: full_note_detector_wrapper_tb
--
-- Description:
--   End-to-end smoke test for the custom note-detector datapath represented in
--   the block design:
--
--     adc_sample_48khz_sampler
--       -> HannROM
--       -> DataProcessorTop
--       -> three bram_sp RAMs
--       -> goertzel_engines_3bank
--
--   The Zynq PS, reset helper, and ILA are not modeled here. This test covers
--   the custom RTL/IP chain that produces NOTE_KEY and NOTE_VALID.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use std.env.all;

entity full_note_detector_wrapper_tb is
end entity full_note_detector_wrapper_tb;

architecture sim of full_note_detector_wrapper_tb is

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz
    constant SOURCE_DIR : string := "";
    constant WATCHDOG_CYCLES : natural := 500_000;

    signal sys_clk : std_logic := '0';
    signal sys_rst : std_logic := '1';

    signal adc_enable      : std_logic := '1';
    signal adc_sample      : signed(23 downto 0);
    signal adc_valid       : std_logic;
    signal adc_index       : unsigned(11 downto 0);
    signal adc_frame_start : std_logic;

    signal hann0      : std_logic_vector(23 downto 0);
    signal hann1      : std_logic_vector(23 downto 0);
    signal hann2      : std_logic_vector(23 downto 0);
    signal hann_addr0 : std_logic_vector(11 downto 0);
    signal hann_addr1 : std_logic_vector(11 downto 0);
    signal hann_addr2 : std_logic_vector(11 downto 0);

    signal ram_data3_wr  : std_logic_vector(23 downto 0);
    signal ram_data12_wr : std_logic_vector(23 downto 0);
    signal ram_data48_wr : std_logic_vector(23 downto 0);
    signal ram_addr3_wr  : std_logic_vector(11 downto 0);
    signal ram_addr12_wr : std_logic_vector(11 downto 0);
    signal ram_addr48_wr : std_logic_vector(11 downto 0);
    signal ram_we3       : std_logic;
    signal ram_we12      : std_logic;
    signal ram_we48      : std_logic;

    signal ram_addr3_rd  : unsigned(11 downto 0);
    signal ram_addr12_rd : unsigned(11 downto 0);
    signal ram_addr48_rd : unsigned(11 downto 0);
    signal ram_data3_rd  : std_logic_vector(23 downto 0);
    signal ram_data12_rd : std_logic_vector(23 downto 0);
    signal ram_data48_rd : std_logic_vector(23 downto 0);

    signal g_en3    : std_logic;
    signal g_en12   : std_logic;
    signal g_en48   : std_logic;
    signal g_done3  : std_logic;
    signal g_done12 : std_logic;
    signal g_done48 : std_logic;

    signal note_key   : unsigned(6 downto 0);
    signal note_valid : std_logic;

begin

    sys_clk <= not sys_clk after CLK_PERIOD / 2;

    adc_source_inst : entity work.adc_sample_48khz_sampler
        generic map (
            CLK_FREQ_HZ    => 50_000_000,
            SAMPLE_RATE_HZ => 48_000,
            MEM_FILE       => SOURCE_DIR & "adc_samples.mem"
        )
        port map (
            clk          => sys_clk,
            rst          => sys_rst,
            enable       => adc_enable,
            sample       => adc_sample,
            sample_valid => adc_valid,
            sample_index => adc_index,
            frame_start  => adc_frame_start
        );

    hann_rom_inst : entity work.HannROM
        port map (
            clk   => sys_clk,
            addr0 => hann_addr0,
            addr1 => hann_addr1,
            addr2 => hann_addr2,
            data0 => hann0,
            data1 => hann1,
            data2 => hann2
        );

    data_processor_inst : entity work.DataProcessorTop
        port map (
            clk        => sys_clk,
            rst        => sys_rst,
            sample     => std_logic_vector(adc_sample),
            hann0      => hann0,
            hann1      => hann1,
            hann2      => hann2,
            hann_addr0 => hann_addr0,
            hann_addr1 => hann_addr1,
            hann_addr2 => hann_addr2,
            ram_addr3  => ram_addr3_wr,
            ram_addr12 => ram_addr12_wr,
            ram_addr48 => ram_addr48_wr,
            ram_data3  => ram_data3_wr,
            ram_data12 => ram_data12_wr,
            ram_data48 => ram_data48_wr,
            RAM_WE3    => ram_we3,
            RAM_WE12   => ram_we12,
            RAM_WE48   => ram_we48,
            G_EN3      => g_en3,
            G_EN12     => g_en12,
            G_EN48     => g_en48,
            G_DONE3    => g_done3,
            G_DONE12   => g_done12,
            G_DONE48   => g_done48
        );

    ram3_inst : entity work.bram_sp
        port map (
            clk    => sys_clk,
            we     => ram_we3,
            w_addr => ram_addr3_wr,
            din    => ram_data3_wr,
            r_addr => std_logic_vector(ram_addr3_rd),
            dout   => ram_data3_rd
        );

    ram12_inst : entity work.bram_sp
        port map (
            clk    => sys_clk,
            we     => ram_we12,
            w_addr => ram_addr12_wr,
            din    => ram_data12_wr,
            r_addr => std_logic_vector(ram_addr12_rd),
            dout   => ram_data12_rd
        );

    ram48_inst : entity work.bram_sp
        port map (
            clk    => sys_clk,
            we     => ram_we48,
            w_addr => ram_addr48_wr,
            din    => ram_data48_wr,
            r_addr => std_logic_vector(ram_addr48_rd),
            dout   => ram_data48_rd
        );

    goertzel_engines_inst : entity work.goertzel_engines_3bank
        generic map (
            BANK1_COEFF_FILE => SOURCE_DIR & "goertzel_bank1_coeff.mem",
            BANK2_COEFF_FILE => SOURCE_DIR & "goertzel_bank2_coeff.mem",
            BANK3_COEFF_FILE => SOURCE_DIR & "goertzel_bank3_coeff.mem"
        )
        port map (
            sys_clk    => sys_clk,
            sys_rst    => sys_rst,
            RAM_DATA3  => signed(ram_data3_rd),
            RAM_DATA12 => signed(ram_data12_rd),
            RAM_DATA48 => signed(ram_data48_rd),
            G_EN3      => g_en3,
            G_EN12     => g_en12,
            G_EN48     => g_en48,
            RAM_ADDR3  => ram_addr3_rd,
            RAM_ADDR12 => ram_addr12_rd,
            RAM_ADDR48 => ram_addr48_rd,
            G_DONE3    => g_done3,
            G_DONE12   => g_done12,
            G_DONE48   => g_done48,
            NOTE_KEY   => note_key,
            NOTE_VALID => note_valid
        );

    trace_proc : process (sys_clk)
        file trace_file : text open write_mode is "full_note_detector_trace.log";
        variable trace_line : line;
        variable cycle_count : natural := 0;
    begin
        if rising_edge(sys_clk) then
            cycle_count := cycle_count + 1;

            if ram_we3 = '1' then
                write(trace_line, string'("WRITE 3 "));
                write(trace_line, cycle_count);
                write(trace_line, string'(" "));
                hwrite(trace_line, ram_addr3_wr);
                write(trace_line, string'(" "));
                hwrite(trace_line, ram_data3_wr);
                writeline(trace_file, trace_line);
            end if;

            if ram_we12 = '1' then
                write(trace_line, string'("WRITE 12 "));
                write(trace_line, cycle_count);
                write(trace_line, string'(" "));
                hwrite(trace_line, ram_addr12_wr);
                write(trace_line, string'(" "));
                hwrite(trace_line, ram_data12_wr);
                writeline(trace_file, trace_line);
            end if;

            if ram_we48 = '1' then
                write(trace_line, string'("WRITE 48 "));
                write(trace_line, cycle_count);
                write(trace_line, string'(" "));
                hwrite(trace_line, ram_addr48_wr);
                write(trace_line, string'(" "));
                hwrite(trace_line, ram_data48_wr);
                writeline(trace_file, trace_line);
            end if;

            if g_done3 = '1' then
                write(trace_line, string'("GDONE 3 "));
                write(trace_line, cycle_count);
                writeline(trace_file, trace_line);
            end if;

            if g_done12 = '1' then
                write(trace_line, string'("GDONE 12 "));
                write(trace_line, cycle_count);
                writeline(trace_file, trace_line);
            end if;

            if g_done48 = '1' then
                write(trace_line, string'("GDONE 48 "));
                write(trace_line, cycle_count);
                writeline(trace_file, trace_line);
            end if;

            if note_valid = '1' then
                write(trace_line, string'("NOTE "));
                write(trace_line, cycle_count);
                write(trace_line, string'(" "));
                write(trace_line, to_integer(note_key));
                writeline(trace_file, trace_line);
            end if;
        end if;
    end process trace_proc;

    stim_proc : process
        variable watchdog      : natural := 0;
        variable saw_g_en3     : boolean := false;
        variable saw_g_en12    : boolean := false;
        variable saw_g_en48    : boolean := false;
        variable saw_g_done3   : boolean := false;
        variable saw_g_done12  : boolean := false;
        variable saw_g_done48  : boolean := false;
    begin
        wait for 5 * CLK_PERIOD;
        wait until rising_edge(sys_clk);
        sys_rst <= '0';

        while watchdog < WATCHDOG_CYCLES loop
            wait until rising_edge(sys_clk);
            wait for 1 ns;
            watchdog := watchdog + 1;

            if g_en3 = '1' then
                saw_g_en3 := true;
            end if;

            if g_en12 = '1' then
                saw_g_en12 := true;
            end if;

            if g_en48 = '1' then
                saw_g_en48 := true;
            end if;

            if g_done3 = '1' then
                saw_g_done3 := true;
            end if;

            if g_done12 = '1' then
                saw_g_done12 := true;
            end if;

            if g_done48 = '1' then
                saw_g_done48 := true;
            end if;

            if note_valid = '1' then
                assert saw_g_en3 and saw_g_en12 and saw_g_en48
                    report "NOTE_VALID asserted before all bank start pulses were observed"
                    severity failure;

                assert saw_g_done3 and saw_g_done12 and saw_g_done48
                    report "NOTE_VALID asserted before all bank done pulses were observed"
                    severity failure;

                assert note_key >= to_unsigned(1, note_key'length) and
                       note_key <= to_unsigned(88, note_key'length)
                    report "NOTE_KEY outside workbook piano-key range 1..88"
                    severity failure;

                report "full_note_detector_wrapper_tb completed successfully. NOTE_KEY=" &
                       integer'image(to_integer(note_key))
                       severity note;
                wait until rising_edge(sys_clk);
                wait for 1 ns;
                finish;
            end if;
        end loop;

        assert saw_g_en3
            report "full_note_detector_wrapper_tb: timeout before G_EN3 was observed"
            severity failure;
        assert saw_g_en12
            report "full_note_detector_wrapper_tb: timeout before G_EN12 was observed"
            severity failure;
        assert saw_g_en48
            report "full_note_detector_wrapper_tb: timeout before G_EN48 was observed"
            severity failure;
        assert false
            report "full_note_detector_wrapper_tb: timeout before NOTE_VALID was observed"
            severity failure;
    end process stim_proc;

end architecture sim;
