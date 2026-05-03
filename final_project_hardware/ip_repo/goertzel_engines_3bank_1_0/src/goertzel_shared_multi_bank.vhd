----------------------------------------------------------------------------------
-- Module Name: goertzel_shared_multi_bank
--
-- Description:
--   Single reusable Goertzel recurrence engine for the three-bank detector.
--
--   The previous wrapper instantiated one complete Goertzel core per bank. That
--   is easy to understand, but it overuses the small Zybo Z7-10 fabric because
--   each core contains wide fixed-point multipliers, adders, and power
--   comparators. This shared core keeps the same math and sample format, but it
--   processes only one bank block at a time. The wrapper chooses which bank is
--   active, streams one 128-sample block, then waits while this core evaluates
--   that block against the selected bank's coefficient table.
--
-- Data and coefficient format:
--   sample_in is signed 24-bit two's-complement Hann-windowed sample data.
--   Coefficients are signed Q2.30 values generated from:
--
--     coeff = 2*cos(2*pi*frequency_hz/bank_sample_rate_hz)
--
--   Raw power remains unsigned 112-bit so the note selector can compare powers
--   directly without square-root or dB conversion.
--
-- Timing:
--   sample_ready is high only when the core is idle and ready for the first
--   sample of a new 128-sample block. bank_select_in is sampled with
--   block_start_in. After the 128-sample recurrence for one bin finishes, the
--   final power equation is pipelined across multiple clock cycles. That keeps
--   the same fixed-point math but avoids one very long square/cross-product/add
--   path at 50 MHz. One raw power is emitted per bin after that pipeline, and
--   block_done_out pulses with the final bin power.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity goertzel_shared_multi_bank is
    generic (
        BANK1_COEFF_FILE : string := "goertzel_bank1_coeff.mem";
        BANK2_COEFF_FILE : string := "goertzel_bank2_coeff.mem";
        BANK3_COEFF_FILE : string := "goertzel_bank3_coeff.mem"
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        bank_select_in   : in  unsigned(1 downto 0);
        sample_ready     : out std_logic;
        sample_in        : in  signed(23 downto 0);
        sample_valid_in  : in  std_logic;
        block_start_in   : in  std_logic;
        block_end_in     : in  std_logic;
        power_out        : out unsigned(111 downto 0);
        power_valid_out  : out std_logic;
        power_bin_index  : out unsigned(5 downto 0);
        power_last_out   : out std_logic;
        block_done_out   : out std_logic
    );
end entity goertzel_shared_multi_bank;

architecture rtl of goertzel_shared_multi_bank is

    constant BLOCK_SIZE      : natural := 128;
    constant SAMPLE_WIDTH    : natural := 24;
    constant COEFF_WIDTH     : natural := 32;
    constant COEFF_FRAC_BITS : natural := 30;
    constant STATE_WIDTH     : natural := 56;
    constant POWER_WIDTH     : natural := 112;

    constant BANK1_BIN_COUNT : natural := 24;
    constant BANK2_BIN_COUNT : natural := 24;
    constant BANK3_BIN_COUNT : natural := 40;
    constant MAX_BIN_COUNT   : natural := 40;

    constant BANK_SEL_3KHZ   : unsigned(1 downto 0) := to_unsigned(0, 2);
    constant BANK_SEL_12KHZ  : unsigned(1 downto 0) := to_unsigned(1, 2);
    constant BANK_SEL_48KHZ  : unsigned(1 downto 0) := to_unsigned(2, 2);

    type coeff_rom_t is array (0 to MAX_BIN_COUNT - 1) of signed(COEFF_WIDTH - 1 downto 0);
    type sample_buffer_t is array (0 to BLOCK_SIZE - 1) of signed(SAMPLE_WIDTH - 1 downto 0);
    type state_t is (
        COLLECT_BLOCK,
        PROCESS_BIN,
        POWER_Q0_SQUARE,
        POWER_Q1_SQUARE,
        POWER_Q0Q1_PRODUCT,
        POWER_COEFF_CROSS,
        POWER_SUM
    );

    impure function init_coeff_rom(file_name : string; expected_count : natural) return coeff_rom_t is
        file coeff_file       : text open read_mode is file_name;
        variable rom_data     : coeff_rom_t := (others => (others => '0'));
        variable current_line : line;
        variable coeff_word   : std_logic_vector(COEFF_WIDTH - 1 downto 0);
        variable read_ok      : boolean;
        variable coeff_index  : natural := 0;
    begin
        while (not endfile(coeff_file)) and (coeff_index < expected_count) loop
            readline(coeff_file, current_line);
            hread(current_line, coeff_word, read_ok);

            assert read_ok
                report "goertzel_shared_multi_bank: invalid coefficient hex at index " &
                       integer'image(coeff_index)
                severity failure;

            rom_data(coeff_index) := signed(coeff_word);
            coeff_index := coeff_index + 1;
        end loop;

        assert coeff_index = expected_count
            report "goertzel_shared_multi_bank: coefficient file has fewer entries than expected"
            severity failure;

        return rom_data;
    end function init_coeff_rom;

    signal coeff_bank1_rom : coeff_rom_t := init_coeff_rom(BANK1_COEFF_FILE, BANK1_BIN_COUNT);
    signal coeff_bank2_rom : coeff_rom_t := init_coeff_rom(BANK2_COEFF_FILE, BANK2_BIN_COUNT);
    signal coeff_bank3_rom : coeff_rom_t := init_coeff_rom(BANK3_COEFF_FILE, BANK3_BIN_COUNT);

    attribute rom_style : string;
    attribute rom_style of coeff_bank1_rom : signal is "distributed";
    attribute rom_style of coeff_bank2_rom : signal is "distributed";
    attribute rom_style of coeff_bank3_rom : signal is "distributed";

    signal state_reg            : state_t := COLLECT_BLOCK;
    signal sample_buffer        : sample_buffer_t := (others => (others => '0'));
    signal collect_index_reg    : natural range 0 to BLOCK_SIZE := 0;
    signal process_index_reg    : natural range 0 to BLOCK_SIZE - 1 := 0;
    signal bin_index_reg        : natural range 0 to MAX_BIN_COUNT - 1 := 0;
    signal active_bank_reg      : unsigned(1 downto 0) := BANK_SEL_3KHZ;
    signal active_bin_count_reg : natural range 1 to MAX_BIN_COUNT := BANK1_BIN_COUNT;
    signal q1_reg               : signed(STATE_WIDTH - 1 downto 0) := (others => '0');
    signal q2_reg               : signed(STATE_WIDTH - 1 downto 0) := (others => '0');

    --------------------------------------------------------------------------
    -- Pipelined power-calculation registers.
    --
    -- The Goertzel recurrence produces final states q0 and q1 for one bin. The
    -- raw power equation is:
    --
    --   power = q0*q0 + q1*q1 - coeff*q0*q1
    --
    -- with the coefficient term shifted right by the Q2.30 fractional scale.
    -- Registering each multiply stage prevents Vivado from building a single
    -- cycle path through multiple wide DSP/carry-chain operations.
    --------------------------------------------------------------------------
    signal final_q0_reg         : signed(STATE_WIDTH - 1 downto 0) := (others => '0');
    signal final_q1_reg         : signed(STATE_WIDTH - 1 downto 0) := (others => '0');
    signal final_coeff_reg      : signed(COEFF_WIDTH - 1 downto 0) := (others => '0');
    signal final_bin_index_reg  : natural range 0 to MAX_BIN_COUNT - 1 := 0;
    signal final_bin_last_reg   : std_logic := '0';
    signal q0_square_reg        : signed((2 * STATE_WIDTH) - 1 downto 0) := (others => '0');
    signal q1_square_reg        : signed((2 * STATE_WIDTH) - 1 downto 0) := (others => '0');
    signal q0q1_product_reg     : signed((2 * STATE_WIDTH) - 1 downto 0) := (others => '0');
    signal coeff_cross_reg      : signed((2 * STATE_WIDTH) + COEFF_WIDTH - 1 downto 0) := (others => '0');

    signal power_out_reg        : unsigned(POWER_WIDTH - 1 downto 0) := (others => '0');
    signal power_valid_reg      : std_logic := '0';
    signal power_bin_index_reg  : unsigned(5 downto 0) := (others => '0');
    signal power_last_reg       : std_logic := '0';
    signal block_done_reg       : std_logic := '0';

begin

    goertzel_proc : process (clk)
        variable sample_ext    : signed(STATE_WIDTH - 1 downto 0);
        variable coeff_current : signed(COEFF_WIDTH - 1 downto 0);
        variable coeff_product : signed(STATE_WIDTH + COEFF_WIDTH - 1 downto 0);
        variable coeff_scaled  : signed(STATE_WIDTH - 1 downto 0);
        variable q0_next       : signed(STATE_WIDTH - 1 downto 0);

        variable cross_scaled  : signed(POWER_WIDTH - 1 downto 0);
        variable power_calc    : signed(POWER_WIDTH - 1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state_reg            <= COLLECT_BLOCK;
                collect_index_reg    <= 0;
                process_index_reg    <= 0;
                bin_index_reg        <= 0;
                active_bank_reg      <= BANK_SEL_3KHZ;
                active_bin_count_reg <= BANK1_BIN_COUNT;
                q1_reg               <= (others => '0');
                q2_reg               <= (others => '0');
                final_q0_reg         <= (others => '0');
                final_q1_reg         <= (others => '0');
                final_coeff_reg      <= (others => '0');
                final_bin_index_reg  <= 0;
                final_bin_last_reg   <= '0';
                q0_square_reg        <= (others => '0');
                q1_square_reg        <= (others => '0');
                q0q1_product_reg     <= (others => '0');
                coeff_cross_reg      <= (others => '0');
                power_out_reg        <= (others => '0');
                power_valid_reg      <= '0';
                power_bin_index_reg  <= (others => '0');
                power_last_reg       <= '0';
                block_done_reg       <= '0';
            else
                power_valid_reg <= '0';
                power_last_reg  <= '0';
                block_done_reg  <= '0';

                case state_reg is
                    when COLLECT_BLOCK =>
                        if sample_valid_in = '1' then
                            ------------------------------------------------------
                            -- block_start_in marks sample 0 and carries the bank
                            -- selection for the entire block. The bin count is
                            -- captured once so PROCESS_BIN knows when that bank's
                            -- coefficient table has been exhausted.
                            ------------------------------------------------------
                            if block_start_in = '1' then
                                sample_buffer(0) <= sample_in;
                                collect_index_reg <= 1;
                                active_bank_reg <= bank_select_in;

                                if bank_select_in = BANK_SEL_3KHZ then
                                    active_bin_count_reg <= BANK1_BIN_COUNT;
                                elsif bank_select_in = BANK_SEL_12KHZ then
                                    active_bin_count_reg <= BANK2_BIN_COUNT;
                                else
                                    active_bin_count_reg <= BANK3_BIN_COUNT;
                                end if;
                            else
                                sample_buffer(collect_index_reg) <= sample_in;
                                collect_index_reg <= collect_index_reg + 1;
                            end if;

                            if block_end_in = '1' then
                                assert (collect_index_reg = BLOCK_SIZE - 1) or
                                       (block_start_in = '1' and BLOCK_SIZE = 1)
                                    report "goertzel_shared_multi_bank: block_end_in before 128 buffered samples"
                                    severity warning;

                                state_reg         <= PROCESS_BIN;
                                process_index_reg <= 0;
                                bin_index_reg     <= 0;
                                q1_reg            <= (others => '0');
                                q2_reg            <= (others => '0');
                                collect_index_reg <= 0;
                            end if;
                        end if;

                    when PROCESS_BIN =>
                        ------------------------------------------------------------------
                        -- Select the coefficient ROM for the active bank. Only one
                        -- multiplier datapath exists, so these ROM muxes replace the
                        -- three full Goertzel datapaths that previously ran in parallel.
                        ------------------------------------------------------------------
                        if active_bank_reg = BANK_SEL_3KHZ then
                            coeff_current := coeff_bank1_rom(bin_index_reg);
                        elsif active_bank_reg = BANK_SEL_12KHZ then
                            coeff_current := coeff_bank2_rom(bin_index_reg);
                        else
                            coeff_current := coeff_bank3_rom(bin_index_reg);
                        end if;

                        sample_ext    := resize(sample_buffer(process_index_reg), STATE_WIDTH);
                        coeff_product := q1_reg * coeff_current;
                        coeff_scaled  := resize(shift_right(coeff_product, COEFF_FRAC_BITS), STATE_WIDTH);
                        q0_next       := sample_ext + coeff_scaled - q2_reg;

                        if process_index_reg = BLOCK_SIZE - 1 then
                            --------------------------------------------------------------
                            -- Latch the final recurrence states and coefficient for the
                            -- pipelined power equation. The final q0 value is q0_next from
                            -- this clock; q1_reg still holds the previous recurrence state.
                            -- The output power is not emitted here because doing all three
                            -- squares/cross-products plus the final add/subtract in one
                            -- 50 MHz cycle creates the timing path that Vivado reported.
                            --------------------------------------------------------------
                            final_q0_reg        <= q0_next;
                            final_q1_reg        <= q1_reg;
                            final_coeff_reg     <= coeff_current;
                            final_bin_index_reg <= bin_index_reg;
                            if bin_index_reg = active_bin_count_reg - 1 then
                                final_bin_last_reg <= '1';
                            else
                                final_bin_last_reg <= '0';
                            end if;

                            process_index_reg <= 0;
                            q1_reg            <= (others => '0');
                            q2_reg            <= (others => '0');
                            state_reg         <= POWER_Q0_SQUARE;
                        else
                            q2_reg <= q1_reg;
                            q1_reg <= q0_next;
                            process_index_reg <= process_index_reg + 1;
                        end if;

                    when POWER_Q0_SQUARE =>
                        ------------------------------------------------------------------
                        -- Stage 1 of the power pipeline: square the newest final
                        -- recurrence state. This register boundary isolates a wide
                        -- multiplier from the remaining power-equation operations.
                        ------------------------------------------------------------------
                        q0_square_reg <= final_q0_reg * final_q0_reg;
                        state_reg <= POWER_Q1_SQUARE;

                    when POWER_Q1_SQUARE =>
                        ------------------------------------------------------------------
                        -- Stage 2: square the previous recurrence state.
                        ------------------------------------------------------------------
                        q1_square_reg <= final_q1_reg * final_q1_reg;
                        state_reg <= POWER_Q0Q1_PRODUCT;

                    when POWER_Q0Q1_PRODUCT =>
                        ------------------------------------------------------------------
                        -- Stage 3: compute q0*q1. The coefficient multiply is delayed to
                        -- the next clock so the cross term is not chained directly after
                        -- this multiplier.
                        ------------------------------------------------------------------
                        q0q1_product_reg <= final_q0_reg * final_q1_reg;
                        state_reg <= POWER_COEFF_CROSS;

                    when POWER_COEFF_CROSS =>
                        ------------------------------------------------------------------
                        -- Stage 4: apply the Q2.30 Goertzel coefficient to q0*q1. The
                        -- following POWER_SUM state performs the fractional shift and
                        -- final add/subtract after this wide product has been registered.
                        ------------------------------------------------------------------
                        coeff_cross_reg <= q0q1_product_reg * final_coeff_reg;
                        state_reg <= POWER_SUM;

                    when POWER_SUM =>
                        ------------------------------------------------------------------
                        -- Final power stage. The arithmetic is intentionally kept in its
                        -- own cycle: scale the cross term back from Q2.30, add the two
                        -- squared terms, subtract the scaled cross term, and saturate any
                        -- negative numerical artifact to zero before the unsigned compare
                        -- logic in the wrapper sees it.
                        ------------------------------------------------------------------
                        cross_scaled := resize(shift_right(coeff_cross_reg, COEFF_FRAC_BITS), POWER_WIDTH);
                        power_calc   := resize(q0_square_reg, POWER_WIDTH) +
                                        resize(q1_square_reg, POWER_WIDTH) -
                                        cross_scaled;

                        if power_calc < to_signed(0, POWER_WIDTH) then
                            power_out_reg <= (others => '0');
                        else
                            power_out_reg <= unsigned(power_calc);
                        end if;

                        power_valid_reg     <= '1';
                        power_bin_index_reg <= to_unsigned(final_bin_index_reg, power_bin_index_reg'length);

                        if final_bin_last_reg = '1' then
                            power_last_reg    <= '1';
                            block_done_reg    <= '1';
                            bin_index_reg     <= 0;
                            process_index_reg <= 0;
                            state_reg         <= COLLECT_BLOCK;
                        else
                            bin_index_reg     <= final_bin_index_reg + 1;
                            process_index_reg <= 0;
                            state_reg         <= PROCESS_BIN;
                        end if;
                end case;
            end if;
        end if;
    end process goertzel_proc;

    --------------------------------------------------------------------------
    -- The core is ready only when it is idle and not holding a partial block.
    -- This prevents the shared wrapper from launching a queued bank while the
    -- final RAM sample of the previous block is still moving through the read
    -- latency pipeline.
    --------------------------------------------------------------------------
    sample_ready    <= '1' when state_reg = COLLECT_BLOCK and collect_index_reg = 0 else '0';
    power_out       <= power_out_reg;
    power_valid_out <= power_valid_reg;
    power_bin_index <= power_bin_index_reg;
    power_last_out  <= power_last_reg;
    block_done_out  <= block_done_reg;

end architecture rtl;
