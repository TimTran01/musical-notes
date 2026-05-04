----------------------------------------------------------------------------------
-- Testbench: goertzel_engines_3bank_tb
--
-- Description:
--   Verifies the diagram-facing Goertzel Engines wrapper. The test drives G_EN
--   for all three banks, models the synchronous RAM DOUT timing, checks that RAM
--   read addresses cover non-overlapping 128-sample blocks, and confirms the
--   wrapper emits one valid workbook piano-key number only after all three bank
--   candidates have completed.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity goertzel_engines_3bank_tb is
end entity goertzel_engines_3bank_tb;

architecture sim of goertzel_engines_3bank_tb is

    constant CLK_PERIOD  : time := 10 ns;
    constant BLOCK_SIZE  : natural := 128;
    constant SOURCE_DIR  : string := "";

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

    signal note_count  : natural := 0;

    function ram_sample(address : unsigned; scale : integer) return signed is
        variable address_int : integer;
    begin
        address_int := to_integer(address);
        return to_signed((address_int * scale) - 4096, 24);
    end function ram_sample;

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
    begin
        if rising_edge(sys_clk) then
            ------------------------------------------------------------------
            -- Model the same synchronous DOUT behavior as the bank RAM:
            -- the sample returned this clock corresponds to the address that was
            -- present at the clock edge.
            ------------------------------------------------------------------
            RAM_DATA3  <= ram_sample(RAM_ADDR3, 3);
            RAM_DATA12 <= ram_sample(RAM_ADDR12, 5);
            RAM_DATA48 <= ram_sample(RAM_ADDR48, 7);
        end if;
    end process ram_model_proc;

    monitor_proc : process (sys_clk)
        variable active3       : boolean := false;
        variable active12      : boolean := false;
        variable active48      : boolean := false;
        variable start3        : boolean := false;
        variable start12       : boolean := false;
        variable start48       : boolean := false;
        variable expected3     : natural := 0;
        variable expected12    : natural := 0;
        variable expected48    : natural := 0;
        variable base3         : natural := 0;
        variable base12        : natural := 0;
        variable base48        : natural := 0;
        variable block3        : natural := 0;
        variable block12       : natural := 0;
        variable block48       : natural := 0;
        variable done3_seen    : boolean := false;
        variable done12_seen   : boolean := false;
        variable done48_seen   : boolean := false;
        variable pending12     : boolean := false;
        variable pending48     : boolean := false;
    begin
        if rising_edge(sys_clk) then
            if sys_rst = '1' then
                active3 := false;
                active12 := false;
                active48 := false;
                start3 := false;
                start12 := false;
                start48 := false;
                expected3 := 0;
                expected12 := 0;
                expected48 := 0;
                base3 := 0;
                base12 := 0;
                base48 := 0;
                block3 := 0;
                block12 := 0;
                block48 := 0;
                done3_seen := false;
                done12_seen := false;
                done48_seen := false;
                pending12 := false;
                pending48 := false;
                note_count <= 0;
            else
                if G_EN3 = '1' then
                    active3 := true;
                    start3 := true;
                    expected3 := 0;
                    base3 := block3 * BLOCK_SIZE;
                    block3 := block3 + 1;
                end if;

                if G_EN12 = '1' then
                    pending12 := true;
                end if;

                if G_EN48 = '1' then
                    pending48 := true;
                end if;

                if active3 then
                    if start3 then
                        start3 := false;
                    else
                        assert RAM_ADDR3 = to_unsigned(base3 + expected3, RAM_ADDR3'length)
                            report "Bank1/3 kHz RAM_ADDR sequence mismatch"
                            severity failure;
                        if expected3 = BLOCK_SIZE - 1 then
                            active3 := false;
                        else
                            expected3 := expected3 + 1;
                        end if;
                    end if;
                end if;

                if active12 then
                    if start12 then
                        start12 := false;
                    else
                        assert RAM_ADDR12 = to_unsigned(base12 + expected12, RAM_ADDR12'length)
                            report "Bank2/12 kHz RAM_ADDR sequence mismatch"
                            severity failure;
                        if expected12 = BLOCK_SIZE - 1 then
                            active12 := false;
                        else
                            expected12 := expected12 + 1;
                        end if;
                    end if;
                end if;

                if active48 then
                    if start48 then
                        start48 := false;
                    else
                        assert RAM_ADDR48 = to_unsigned(base48 + expected48, RAM_ADDR48'length)
                            report "Bank3/48 kHz RAM_ADDR sequence mismatch"
                            severity failure;
                        if expected48 = BLOCK_SIZE - 1 then
                            active48 := false;
                        else
                            expected48 := expected48 + 1;
                        end if;
                    end if;
                end if;

                if G_DONE3 = '1' then
                    done3_seen := true;

                    ------------------------------------------------------------------
                    -- The resource-saving wrapper services one bank at a time. For the
                    -- simultaneous launch in this test, Bank2 starts after Bank1 has
                    -- completed because the scheduler priority is 3 kHz, then 12 kHz,
                    -- then 48 kHz.
                    ------------------------------------------------------------------
                    if pending12 then
                        active12 := true;
                        start12 := false;
                        expected12 := 1;
                        base12 := block12 * BLOCK_SIZE;
                        block12 := block12 + 1;
                        pending12 := false;
                    end if;
                end if;
                if G_DONE12 = '1' then
                    done12_seen := true;

                    if pending48 then
                        active48 := true;
                        start48 := false;
                        expected48 := 1;
                        base48 := block48 * BLOCK_SIZE;
                        block48 := block48 + 1;
                        pending48 := false;
                    end if;
                end if;
                if G_DONE48 = '1' then
                    done48_seen := true;
                end if;

                if NOTE_VALID = '1' then
                    ------------------------------------------------------------------
                    -- The public Goertzel wrapper now hides raw powers and emits one
                    -- piano-key decision. A note cannot be valid until every bank has
                    -- completed at least one block candidate.
                    ------------------------------------------------------------------
                    assert done3_seen and done12_seen and done48_seen
                        report "NOTE_VALID asserted before all three banks completed"
                        severity failure;
                    assert NOTE_KEY >= to_unsigned(1, NOTE_KEY'length) and
                           NOTE_KEY <= to_unsigned(88, NOTE_KEY'length)
                        report "NOTE_KEY outside workbook piano-key range 1..88"
                        severity failure;

                    note_count <= note_count + 1;
                    done3_seen := false;
                    done12_seen := false;
                    done48_seen := false;
                end if;
            end if;
        end if;
    end process monitor_proc;

    stim_proc : process
        variable saw_done3  : boolean;
        variable saw_done12 : boolean;
        variable saw_done48 : boolean;
        variable watchdog   : natural;
    begin
        wait for 4 * CLK_PERIOD;
        wait until rising_edge(sys_clk);
        sys_rst <= '0';

        ----------------------------------------------------------------------
        -- Launch all banks together. This intentionally creates simultaneous
        -- start requests and verifies that the wrapper queues them for the
        -- single shared Goertzel core instead of dropping one-clock G_EN pulses.
        ----------------------------------------------------------------------
        wait until rising_edge(sys_clk);
        G_EN3  <= '1';
        G_EN12 <= '1';
        G_EN48 <= '1';
        wait until rising_edge(sys_clk);
        G_EN3  <= '0';
        G_EN12 <= '0';
        G_EN48 <= '0';

        saw_done3  := false;
        saw_done12 := false;
        saw_done48 := false;
        watchdog   := 0;
        while not (saw_done3 and saw_done12 and saw_done48) loop
            wait until rising_edge(sys_clk);
            wait for 1 ns;
            watchdog := watchdog + 1;

            assert watchdog < 20000
                report "Timeout waiting for first three Goertzel bank completions"
                severity failure;

            if G_DONE3 = '1' then
                saw_done3 := true;
            end if;
            if G_DONE12 = '1' then
                saw_done12 := true;
            end if;
            if G_DONE48 = '1' then
                saw_done48 := true;
            end if;
        end loop;

        wait for 20 * CLK_PERIOD;

        assert note_count = 1
            report "Wrapper did not emit exactly one global NOTE_VALID pulse"
            severity failure;

        ----------------------------------------------------------------------
        -- Launch a second Bank1 block to prove the RAM reader advances from
        -- addresses 0..127 to 128..255 instead of rereading the same block.
        ----------------------------------------------------------------------
        wait until rising_edge(sys_clk);
        G_EN3 <= '1';
        wait until rising_edge(sys_clk);
        G_EN3 <= '0';

        watchdog := 0;
        loop
            wait until rising_edge(sys_clk);
            wait for 1 ns;
            watchdog := watchdog + 1;

            assert watchdog < 6000
                report "Timeout waiting for second Bank1/3 kHz completion"
                severity failure;

            exit when G_DONE3 = '1';
        end loop;

        wait for 20 * CLK_PERIOD;

        assert note_count = 1
            report "Second Bank1/3 kHz block incorrectly emitted a global note without fresh Bank2/Bank3 candidates"
            severity failure;

        report "goertzel_engines_3bank_tb completed successfully" severity note;
        finish;
    end process stim_proc;

end architecture sim;
