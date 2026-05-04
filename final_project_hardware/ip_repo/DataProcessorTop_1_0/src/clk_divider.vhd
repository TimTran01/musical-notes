----------------------------------------------------------------------------------
-- Module Name: clk_divider
--
-- Description:
--   Independent integer clock dividers for the three preprocessing banks.
--
--   The input clock is the 50 MHz block-design clock. Each output toggles after
--   its own terminal count, giving the controller separate 3 kHz, 12 kHz, and
--   48 kHz divided clocks for bank scheduling. The reset input is active high
--   and asynchronous to match the existing controller/datapath reset style.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity clk_divider is
    Port (
        clk_in  : in  STD_LOGIC;        -- 50 MHz input
        reset   : in  STD_LOGIC;        -- Asynchronous reset
        clk_out_3 : out STD_LOGIC;      -- 3 kHz output
        clk_out_12 : out STD_LOGIC;     -- 12 kHz output
        clk_out_48 : out STD_LOGIC      -- 48 kHz output
    );
end clk_divider;

architecture arch of clk_divider is

    constant CLK_FREQ_HZ    : natural := 50_000_000;
    constant SAMPLE_RATE_HZ : natural := 48_000;

    signal phase_accumulator : natural range 0 to CLK_FREQ_HZ - 1 := 0;
    signal div4_count        : unsigned(1 downto 0) := (others => '0');
    signal div16_count       : unsigned(3 downto 0) := (others => '0');

    signal tick_48 : std_logic := '0';
    signal tick_12 : std_logic := '0';
    signal tick_3  : std_logic := '0';

begin

    process(clk_in, reset)
        variable next_phase : natural range 0 to CLK_FREQ_HZ + SAMPLE_RATE_HZ;
    begin
        if reset = '1' then
            phase_accumulator <= 0;
            div4_count        <= (others => '0');
            div16_count       <= (others => '0');
            tick_48           <= '0';
            tick_12           <= '0';
            tick_3            <= '0';
        elsif rising_edge(clk_in) then
            tick_48 <= '0';
            tick_12 <= '0';
            tick_3  <= '0';

            next_phase := phase_accumulator + SAMPLE_RATE_HZ;
            if next_phase >= CLK_FREQ_HZ then
                phase_accumulator <= next_phase - CLK_FREQ_HZ;
                tick_48 <= '1';

                if div4_count = "00" then
                    tick_12 <= '1';
                end if;

                if div16_count = "0000" then
                    tick_3 <= '1';
                end if;

                div4_count  <= div4_count + 1;
                div16_count <= div16_count + 1;
            else
                phase_accumulator <= next_phase;
            end if;
        end if;
    end process;

    clk_out_48 <= tick_48;
    clk_out_12 <= tick_12;
    clk_out_3  <= tick_3;

end arch;
