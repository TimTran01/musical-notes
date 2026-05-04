library ieee;
use ieee.std_logic_1164.all;

entity note_event_latch_tb is
end entity note_event_latch_tb;

architecture sim of note_event_latch_tb is
    constant CLK_PERIOD : time := 20 ns;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal note_key    : std_logic_vector(6 downto 0) := (others => '0');
    signal note_valid  : std_logic := '0';
    signal clear       : std_logic_vector(0 downto 0) := (others => '0');
    signal latched_key : std_logic_vector(6 downto 0);
    signal pending     : std_logic;
    signal irq         : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.note_event_latch
        port map (
            clk         => clk,
            rst         => rst,
            note_key    => note_key,
            note_valid  => note_valid,
            clear       => clear,
            latched_key => latched_key,
            pending     => pending,
            irq         => irq
        );

    stim_proc : process
    begin
        wait for 4 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        note_key   <= "0110001"; -- 49, A4
        note_valid <= '1';
        wait until rising_edge(clk);
        note_valid <= '0';
        wait until rising_edge(clk);

        assert latched_key = "0110001"
            report "latched key did not capture note event"
            severity failure;
        assert pending = '1' and irq = '1'
            report "pending/irq did not assert"
            severity failure;

        clear <= "1";
        wait until rising_edge(clk);
        clear <= "0";
        wait until rising_edge(clk);

        assert pending = '0' and irq = '0'
            report "clear did not drop pending/irq"
            severity failure;
        assert latched_key = "0110001"
            report "clear unexpectedly changed latched key"
            severity failure;

        clear      <= "1";
        note_key   <= "0110010"; -- 50
        note_valid <= '1';
        wait until rising_edge(clk);
        clear      <= "0";
        note_valid <= '0';
        wait until rising_edge(clk);

        assert latched_key = "0110010"
            report "simultaneous clear and valid did not keep new note"
            severity failure;
        assert pending = '1' and irq = '1'
            report "simultaneous clear and valid did not assert pending"
            severity failure;

        report "note_event_latch_tb completed successfully" severity note;
        wait;
    end process;
end architecture sim;
