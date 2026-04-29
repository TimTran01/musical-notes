----------------------------------------------------------------------------------
-- Testbench: adc_sample_48khz_sampler_tb
--
-- Description:
--   Self-checking simulation for the 48 kHz ADC sample source. The testbench
--   verifies the fractional timing pattern for a 50 MHz clock and verifies
--   address wrap behavior with a faster generic ratio so the wrap test completes
--   quickly in simulation.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity adc_sample_48khz_sampler_tb is
end entity adc_sample_48khz_sampler_tb;

architecture sim of adc_sample_48khz_sampler_tb is

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    signal clk    : std_logic := '0';
    signal rst    : std_logic := '1';
    signal enable : std_logic := '0';

    signal sample_48k       : signed(23 downto 0);
    signal sample_valid_48k : std_logic;
    signal sample_index_48k : unsigned(11 downto 0);
    signal frame_start_48k  : std_logic;

    signal sample_wrap       : signed(23 downto 0);
    signal sample_valid_wrap : std_logic;
    signal sample_index_wrap : unsigned(11 downto 0);
    signal frame_start_wrap  : std_logic;

    signal timing_test_done : boolean := false;
    signal wrap_test_done   : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2;

    --------------------------------------------------------------------------
    -- Primary DUT.
    --
    -- This instance uses the intended 50 MHz clock and 48 kHz sample rate.
    --------------------------------------------------------------------------
    dut_48k : entity work.adc_sample_48khz_sampler
        generic map (
            CLK_FREQ_HZ    => 50_000_000,
            SAMPLE_RATE_HZ => 48_000,
            MEM_FILE       => "adc_samples.mem"
        )
        port map (
            clk          => clk,
            rst          => rst,
            enable       => enable,
            sample       => sample_48k,
            sample_valid => sample_valid_48k,
            sample_index => sample_index_48k,
            frame_start  => frame_start_48k
        );

    --------------------------------------------------------------------------
    -- Fast wrap DUT.
    --
    -- This instance uses the same RTL but a faster generic ratio. It lets the
    -- testbench reach address 4095 and wrap back to 0 without simulating a full
    -- 85 ms frame at the real 48 kHz rate.
    --------------------------------------------------------------------------
    dut_wrap : entity work.adc_sample_48khz_sampler
        generic map (
            CLK_FREQ_HZ    => 2,
            SAMPLE_RATE_HZ => 1,
            MEM_FILE       => "adc_samples.mem"
        )
        port map (
            clk          => clk,
            rst          => rst,
            enable       => enable,
            sample       => sample_wrap,
            sample_valid => sample_valid_wrap,
            sample_index => sample_index_wrap,
            frame_start  => frame_start_wrap
        );

    --------------------------------------------------------------------------
    -- Reset and enable sequence.
    --------------------------------------------------------------------------
    control_proc : process
    begin
        wait for 5 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst    <= '0';
        enable <= '1';
        wait;
    end process control_proc;

    --------------------------------------------------------------------------
    -- Verify the real 50 MHz / 48 kHz fractional accumulator behavior.
    --
    -- With this ratio, sample_valid intervals must be either 1041 or 1042 clock
    -- cycles. The average over time is exactly 48 kHz.
    --------------------------------------------------------------------------
    timing_check_proc : process
        variable clock_count      : natural := 0;
        variable last_valid_clock : natural := 0;
        variable valid_count      : natural := 0;
        variable expected_index   : natural := 0;
        variable interval         : natural := 0;
    begin
        wait until rst = '0';

        while valid_count < 24 loop
            wait until rising_edge(clk);
            clock_count := clock_count + 1;

            if sample_valid_48k = '1' then
                if valid_count = 0 then
                    assert sample_index_48k = to_unsigned(0, sample_index_48k'length)
                        report "First 48 kHz sample was not index 0"
                        severity failure;

                    assert frame_start_48k = '1'
                        report "frame_start was not asserted with first sample"
                        severity failure;
                else
                    interval := clock_count - last_valid_clock;

                    assert (interval = 1041) or (interval = 1042)
                        report "48 kHz sample interval was not 1041 or 1042 clocks"
                        severity failure;

                    assert sample_index_48k = to_unsigned(expected_index, sample_index_48k'length)
                        report "48 kHz sample_index did not increment with sample_valid"
                        severity failure;

                    assert frame_start_48k = '0'
                        report "frame_start asserted away from sample index 0"
                        severity failure;
                end if;

                last_valid_clock := clock_count;
                valid_count      := valid_count + 1;
                expected_index   := expected_index + 1;
            end if;
        end loop;

        timing_test_done <= true;
        wait;
    end process timing_check_proc;

    --------------------------------------------------------------------------
    -- Verify wrap from address 4095 back to address 0 and the frame_start pulse.
    --------------------------------------------------------------------------
    wrap_check_proc : process
        variable valid_count    : natural := 0;
        variable expected_index : natural := 0;
    begin
        wait until rst = '0';

        while valid_count < 4098 loop
            wait until rising_edge(clk);

            if sample_valid_wrap = '1' then
                assert sample_index_wrap = to_unsigned(expected_index, sample_index_wrap'length)
                    report "Wrap test sample_index mismatch"
                    severity failure;

                if expected_index = 0 then
                    assert frame_start_wrap = '1'
                        report "frame_start missing at sample index 0"
                        severity failure;
                else
                    assert frame_start_wrap = '0'
                        report "frame_start asserted away from sample index 0"
                        severity failure;
                end if;

                if expected_index = 4095 then
                    expected_index := 0;
                else
                    expected_index := expected_index + 1;
                end if;

                valid_count := valid_count + 1;
            end if;
        end loop;

        wrap_test_done <= true;
        wait;
    end process wrap_check_proc;

    --------------------------------------------------------------------------
    -- End-of-test message.
    --------------------------------------------------------------------------
    done_proc : process
    begin
        wait until timing_test_done and wrap_test_done;
        report "adc_sample_48khz_sampler_tb completed successfully" severity note;
        finish;
        wait;
    end process done_proc;

end architecture sim;
