----------------------------------------------------------------------------------
-- Testbench: adc_sample_rom_tb
--
-- Description:
--   Self-checking simulation for adc_sample_rom. The fixture memory file is
--   intentionally short so that the four signed boundary cases are easy to
--   inspect by hand:
--
--     000001 ->  +1
--     FFFFFF ->  -1
--     800000 ->  minimum signed 24-bit value
--     7FFFFF ->  maximum signed 24-bit value
--
--   Production ADC sample files should contain all 4096 lines.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adc_sample_rom_tb is
end entity adc_sample_rom_tb;

architecture sim of adc_sample_rom_tb is

    constant CLK_PERIOD : time := 10 ns;

    signal clk    : std_logic := '0';
    signal en     : std_logic := '0';
    signal addr   : unsigned(11 downto 0) := (others => '0');
    signal sample : signed(23 downto 0);

begin

    --------------------------------------------------------------------------
    -- Clock generation.
    --
    -- A simple 100 MHz clock is sufficient for verifying the ROM read timing.
    --------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    --------------------------------------------------------------------------
    -- Device under test.
    --
    -- The generic points at the compact simulation memory file. The production
    -- design can keep the default generic value, adc_samples.mem.
    --------------------------------------------------------------------------
    dut : entity work.adc_sample_rom
        generic map (
            MEM_FILE => "adc_sample_rom_tb.mem"
        )
        port map (
            clk    => clk,
            en     => en,
            addr   => addr,
            sample => sample
        );

    --------------------------------------------------------------------------
    -- Stimulus and checks.
    --
    -- Because adc_sample_rom uses a synchronous read, each expected value is
    -- checked one rising clock after the address and enable are applied.
    --------------------------------------------------------------------------
    stim_proc : process
    begin
        wait for CLK_PERIOD;

        en   <= '1';
        addr <= to_unsigned(0, addr'length);
        wait until rising_edge(clk);
        wait for 1 ns;
        assert sample = to_signed(1, sample'length)
            report "Address 0 did not decode 000001 as +1"
            severity failure;

        addr <= to_unsigned(1, addr'length);
        wait until rising_edge(clk);
        wait for 1 ns;
        assert sample = to_signed(-1, sample'length)
            report "Address 1 did not decode FFFFFF as -1"
            severity failure;

        addr <= to_unsigned(2, addr'length);
        wait until rising_edge(clk);
        wait for 1 ns;
        assert sample = to_signed(-8388608, sample'length)
            report "Address 2 did not decode 800000 as minimum signed 24-bit value"
            severity failure;

        addr <= to_unsigned(3, addr'length);
        wait until rising_edge(clk);
        wait for 1 ns;
        assert sample = to_signed(8388607, sample'length)
            report "Address 3 did not decode 7FFFFF as maximum signed 24-bit value"
            severity failure;

        ----------------------------------------------------------------------
        -- Verify enable hold behavior. Changing the address while en='0' must
        -- leave the registered output unchanged.
        ----------------------------------------------------------------------
        en   <= '0';
        addr <= to_unsigned(0, addr'length);
        wait until rising_edge(clk);
        wait for 1 ns;
        assert sample = to_signed(8388607, sample'length)
            report "sample changed while en was deasserted"
            severity failure;

        report "adc_sample_rom_tb completed successfully" severity note;
        wait;
    end process stim_proc;

end architecture sim;
