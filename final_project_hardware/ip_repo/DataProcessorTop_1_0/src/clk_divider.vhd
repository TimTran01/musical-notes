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

    -- 48 kHz divider state. Toggling every 522 input clocks produces the
    -- closest integer-divided square wave from the 50 MHz system clock.
    signal counter_48 : integer range 0 to 521 := 0;
    signal temporal_48: STD_LOGIC := '0';

    -- 12 kHz divider state.
    signal counter_12 : integer range 0 to 2083 := 0;
    signal temporal_12: STD_LOGIC := '0';

    -- 3 kHz divider state.
    signal counter_3 : integer range 0 to 8333 := 0;
    signal temporal_3: STD_LOGIC := '0';

begin

p_48kHz:  process(clk_in, reset)
    begin
        if reset = '1' then
            temporal_48 <= '0';
            counter_48  <= 0;
        elsif rising_edge(clk_in) then
            if counter_48 = 521 then
                temporal_48 <= NOT(temporal_48);
                counter_48  <= 0;
            else
                counter_48 <= counter_48 + 1;
            end if;
        end if;
    end process;

 p_12kHz:  process(clk_in, reset)
    begin
        if reset = '1' then
            temporal_12 <= '0';
            counter_12  <= 0;
        elsif rising_edge(clk_in) then
            if counter_12 = 2083 then
                temporal_12 <= NOT(temporal_12);
                counter_12  <= 0;
            else
                counter_12 <= counter_12 + 1;
            end if;
        end if;
    end process;

 p_3kHz:  process(clk_in, reset)
    begin
        if reset = '1' then
            temporal_3 <= '0';
            counter_3  <= 0;
        elsif rising_edge(clk_in) then
            if counter_3 = 8333 then
                temporal_3 <= NOT(temporal_3);
                counter_3  <= 0;
            else
                counter_3 <= counter_3 + 1;
            end if;
        end if;
    end process;

    clk_out_48 <= temporal_48;
    clk_out_12 <= temporal_12;
    clk_out_3 <= temporal_3;

end arch;
