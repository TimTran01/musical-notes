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

    -- Counter to hold values up to 521 (9 bits is enough)
    signal counter_48 : integer range 0 to 521 := 0;
    signal temporal_48: STD_LOGIC := '0';
    
    -- Counter to hold values up to 521 (9 bits is enough)
    signal counter_12 : integer range 0 to 2083 := 0;
    signal temporal_12: STD_LOGIC := '0';
    
    -- Counter to hold values up to 521 (9 bits is enough)
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