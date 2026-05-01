----------------------------------------------------------------------------------
-- Testbench: hann_window_bank1_ram_tb
--
-- Description:
--   Self-checking simulation for the bank-1 Hann RAM IP. The testbench drives a
--   deterministic 24-bit sample stream, verifies the decimate-by-16 write
--   cadence, reads back selected RAM addresses, confirms stop-on-full behavior,
--   and checks reset/restart.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity hann_window_bank1_ram_tb is
end entity hann_window_bank1_ram_tb;

architecture sim of hann_window_bank1_ram_tb is

    constant CLK_PERIOD       : time := 10 ns;
    constant RAM_DEPTH        : natural := 4096;
    constant ADDR_WIDTH       : natural := 12;
    constant DATA_WIDTH       : natural := 24;
    constant DECIMATION_RATIO : natural := 16;

    subtype sample_t is signed(DATA_WIDTH - 1 downto 0);

    type natural_array_t is array (natural range <>) of natural;

    constant READBACK_ADDRS : natural_array_t := (
        0,
        1,
        2,
        127,
        2048,
        4095
    );

    signal clk             : std_logic := '0';
    signal rst             : std_logic := '1';
    signal sample_in       : sample_t := (others => '0');
    signal sample_valid_in : std_logic := '0';
    signal frame_start_in  : std_logic := '0';
    signal read_addr       : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal read_data       : sample_t;
    signal capture_done    : std_logic;
    signal write_count     : unsigned(12 downto 0);

    function sample_for_valid(valid_index : natural) return sample_t is
    begin
        return to_signed((integer(valid_index) * 17) - 5000, DATA_WIDTH);
    end function sample_for_valid;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.hann_window_bank1_ram
        port map (
            clk             => clk,
            rst             => rst,
            sample_in       => sample_in,
            sample_valid_in => sample_valid_in,
            frame_start_in  => frame_start_in,
            read_addr       => read_addr,
            read_data       => read_data,
            capture_done    => capture_done,
            write_count     => write_count
        );

    stim_proc : process
        procedure drive_valid(valid_index : natural; frame_start : std_logic := '0') is
        begin
            sample_in       <= sample_for_valid(valid_index);
            sample_valid_in <= '1';
            frame_start_in  <= frame_start;
            wait until rising_edge(clk);
            wait for 1 ns;
            sample_valid_in <= '0';
            frame_start_in  <= '0';
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure drive_valid;

        procedure read_and_expect(addr : natural; expected : sample_t) is
        begin
            read_addr <= to_unsigned(addr, ADDR_WIDTH);
            wait until rising_edge(clk);
            wait for 1 ns;

            assert read_data = expected
                report "RAM readback mismatch at address " & integer'image(addr)
                severity failure;
        end procedure read_and_expect;

        variable expected_count : natural;
    begin
        wait for 4 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait for 1 ns;

        assert capture_done = '0'
            report "capture_done asserted immediately after reset"
            severity failure;

        assert write_count = to_unsigned(0, write_count'length)
            report "write_count was not zero after reset"
            severity failure;

        -- Valid samples before frame_start_in must be ignored.
        for valid_index in 0 to 7 loop
            drive_valid(valid_index);
        end loop;

        assert write_count = to_unsigned(0, write_count'length)
            report "RAM wrote samples before frame_start_in"
            severity failure;

        -- A frame_start without valid data arms the capture but does not write.
        frame_start_in <= '1';
        sample_valid_in <= '0';
        sample_in <= sample_for_valid(100);
        wait until rising_edge(clk);
        wait for 1 ns;
        frame_start_in <= '0';

        assert write_count = to_unsigned(0, write_count'length)
            report "RAM wrote on frame_start without sample_valid_in"
            severity failure;

        -- First valid sample after frame_start is stored at address 0.
        drive_valid(0);

        assert write_count = to_unsigned(1, write_count'length)
            report "first valid sample after frame_start was not captured"
            severity failure;

        -- Fifteen more valid samples are skipped.
        for valid_index in 1 to DECIMATION_RATIO - 1 loop
            drive_valid(valid_index);

            assert write_count = to_unsigned(1, write_count'length)
                report "RAM wrote before the 16-sample decimation interval elapsed"
                severity failure;
        end loop;

        -- The 16th valid sample after the first write is captured at address 1.
        drive_valid(DECIMATION_RATIO);

        assert write_count = to_unsigned(2, write_count'length)
            report "RAM did not capture the second decimated sample"
            severity failure;

        -- Complete the capture through address 4095.
        for valid_index in DECIMATION_RATIO + 1 to (RAM_DEPTH - 1) * DECIMATION_RATIO loop
            drive_valid(valid_index);
        end loop;

        assert write_count = to_unsigned(RAM_DEPTH, write_count'length)
            report "write_count did not reach RAM depth after full capture"
            severity failure;

        assert capture_done = '1'
            report "capture_done did not assert after 4096 stored samples"
            severity failure;

        -- Extra valid samples after completion must not overwrite RAM.
        for valid_index in (RAM_DEPTH * DECIMATION_RATIO) to (RAM_DEPTH * DECIMATION_RATIO) + 63 loop
            drive_valid(valid_index);
        end loop;

        assert write_count = to_unsigned(RAM_DEPTH, write_count'length)
            report "write_count changed after capture_done"
            severity failure;

        assert capture_done = '1'
            report "capture_done deasserted after extra input samples"
            severity failure;

        for vector_index in READBACK_ADDRS'range loop
            expected_count := READBACK_ADDRS(vector_index) * DECIMATION_RATIO;
            read_and_expect(
                READBACK_ADDRS(vector_index),
                sample_for_valid(expected_count)
            );
        end loop;

        -- Reset should restart capture from address 0.
        rst <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        rst <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert write_count = to_unsigned(0, write_count'length)
            report "write_count did not clear after reset"
            severity failure;

        assert capture_done = '0'
            report "capture_done did not clear after reset"
            severity failure;

        drive_valid(777, '1');

        assert write_count = to_unsigned(1, write_count'length)
            report "RAM did not restart capture after reset"
            severity failure;

        read_and_expect(0, sample_for_valid(777));

        report "hann_window_bank1_ram_tb completed successfully" severity note;
        finish;
    end process stim_proc;

end architecture sim;
