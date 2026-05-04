----------------------------------------------------------------------------------
-- Module Name: note_event_latch
--
-- Description:
--   Latches the one-cycle hardware note decision so software can read it through
--   AXI GPIO and receive a level-sensitive interrupt until the event is cleared.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity note_event_latch is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        note_key    : in  std_logic_vector(6 downto 0);
        note_valid  : in  std_logic;
        clear       : in  std_logic_vector(0 downto 0);
        latched_key : out std_logic_vector(6 downto 0);
        pending     : out std_logic;
        irq         : out std_logic
    );
end entity note_event_latch;

architecture rtl of note_event_latch is
    signal key_reg     : std_logic_vector(6 downto 0) := (others => '0');
    signal pending_reg : std_logic := '0';
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                key_reg     <= (others => '0');
                pending_reg <= '0';
            elsif note_valid = '1' then
                key_reg     <= note_key;
                pending_reg <= '1';
            elsif clear(0) = '1' then
                pending_reg <= '0';
            end if;
        end if;
    end process;

    latched_key <= key_reg;
    pending     <= pending_reg;
    irq         <= pending_reg;
end architecture rtl;
