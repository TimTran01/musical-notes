----------------------------------------------------------------------------------
-- Module Name: goertzel_engines_3bank
--
-- Description:
--   Diagram-facing Goertzel Engines wrapper for all three note banks.
--
--   This IP replaces the visible per-bank RAM readers and Goertzel cores in the
--   block design. Its public ports follow the drawing: each bank has a RAM data
--   input, a RAM address output, a G_EN start input, and a G_DONE completion
--   output. Internally, this wrapper latches each bank's G_EN request and uses
--   one shared Goertzel core to read and process the pending 128-sample blocks.
--   Sharing the core is required for the Zybo Z7-10 because three parallel
--   Goertzel datapaths overuse LUT, carry-chain, and DSP resources.
--
-- Note output:
--   Raw Goertzel powers are still produced inside the shared core because the
--   note detector must compare those powers to find the strongest frequency bin.
--   This wrapper no longer exposes that debug stream to the block design.
--   Instead, it tracks the strongest bin for each completed bank block, maps
--   that bin to the workbook piano-key number, and emits one global NOTE_KEY
--   after all three banks have produced a fresh candidate.
--
-- Selection policy:
--   NOTE_KEY is an unsigned piano key number from 1 to 88. NOTE_VALID pulses for
--   one sys_clk cycle when a new global decision is available. No threshold is
--   applied in this step, so the strongest available power always wins. Exact
--   ties keep the lower piano key because comparisons update only on strictly
--   greater power. The decision is registered one sys_clk after the final bank
--   candidate becomes visible at this wrapper boundary.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity goertzel_engines_3bank is
    generic (
        ----------------------------------------------------------------------
        -- Coefficient file paths.
        --
        -- Vivado out-of-context IP synthesis runs from a generated run
        -- directory, not from the source directory. These generics let the
        -- block-design script pass absolute .mem paths so the TextIO ROM
        -- initialization functions can open the files reliably during
        -- synthesis and simulation.
        ----------------------------------------------------------------------
        BANK1_COEFF_FILE : string := "goertzel_bank1_coeff.mem";
        BANK2_COEFF_FILE : string := "goertzel_bank2_coeff.mem";
        BANK3_COEFF_FILE : string := "goertzel_bank3_coeff.mem"
    );
    port (
        sys_clk     : in  std_logic;
        sys_rst     : in  std_logic;
        RAM_DATA3   : in  signed(23 downto 0);
        RAM_DATA12  : in  signed(23 downto 0);
        RAM_DATA48  : in  signed(23 downto 0);
        G_EN3       : in  std_logic;
        G_EN12      : in  std_logic;
        G_EN48      : in  std_logic;
        RAM_ADDR3   : out unsigned(11 downto 0);
        RAM_ADDR12  : out unsigned(11 downto 0);
        RAM_ADDR48  : out unsigned(11 downto 0);
        G_DONE3     : out std_logic;
        G_DONE12    : out std_logic;
        G_DONE48    : out std_logic;
        NOTE_KEY    : out unsigned(6 downto 0);
        NOTE_VALID  : out std_logic
    );
end entity goertzel_engines_3bank;

architecture rtl of goertzel_engines_3bank is

    --------------------------------------------------------------------------
    -- Bank and output constants.
    --
    -- The Goertzel core reports a bin number local to each bank. These first
    -- key constants convert that local bin into the workbook piano-key number:
    --   Bank1/3 kHz  bin 0..23 -> key 1..24
    --   Bank2/12 kHz bin 0..23 -> key 25..48
    --   Bank3/48 kHz bin 0..39 -> key 49..88
    --------------------------------------------------------------------------
    constant RAM_DEPTH       : natural := 4096;
    constant BLOCK_SIZE      : natural := 128;
    constant BLOCK_COUNT     : natural := RAM_DEPTH / BLOCK_SIZE;
    constant POWER_WIDTH     : natural := 112;
    constant NOTE_WIDTH      : natural := 7;
    constant BANK1_FIRST_KEY : natural := 1;
    constant BANK2_FIRST_KEY : natural := 25;
    constant BANK3_FIRST_KEY : natural := 49;
    constant BANK_SEL_3KHZ   : unsigned(1 downto 0) := to_unsigned(0, 2);
    constant BANK_SEL_12KHZ  : unsigned(1 downto 0) := to_unsigned(1, 2);
    constant BANK_SEL_48KHZ  : unsigned(1 downto 0) := to_unsigned(2, 2);

    function bin_to_key(first_key : natural; bin_index : unsigned) return unsigned is
    begin
        return to_unsigned(first_key + to_integer(bin_index), NOTE_WIDTH);
    end function bin_to_key;

    function ram_addr_for(block_number : natural; sample_offset : natural) return unsigned is
    begin
        return to_unsigned((block_number * BLOCK_SIZE) + sample_offset, 12);
    end function ram_addr_for;

    function hex_char(nibble : natural) return character is
    begin
        case nibble is
            when 0  => return '0';
            when 1  => return '1';
            when 2  => return '2';
            when 3  => return '3';
            when 4  => return '4';
            when 5  => return '5';
            when 6  => return '6';
            when 7  => return '7';
            when 8  => return '8';
            when 9  => return '9';
            when 10 => return 'A';
            when 11 => return 'B';
            when 12 => return 'C';
            when 13 => return 'D';
            when 14 => return 'E';
            when 15 => return 'F';
            when others => return '?';
        end case;
    end function hex_char;

    function unsigned_to_hex(value : unsigned) return string is
        constant NIBBLES : natural := (value'length + 3) / 4;
        variable result  : string(1 to NIBBLES);
        variable padded  : unsigned(NIBBLES * 4 - 1 downto 0) := (others => '0');
        variable nibble  : natural range 0 to 15;
    begin
        padded(value'length - 1 downto 0) := value;

        for i in 0 to NIBBLES - 1 loop
            nibble := to_integer(padded(((NIBBLES - i) * 4) - 1 downto ((NIBBLES - i - 1) * 4)));
            result(i + 1) := hex_char(nibble);
        end loop;

        return result;
    end function unsigned_to_hex;

    type reader_state_t is (IDLE, STREAM_BLOCK);

    signal reader_state_reg     : reader_state_t := IDLE;
    signal request3_pending     : std_logic := '0';
    signal request12_pending    : std_logic := '0';
    signal request48_pending    : std_logic := '0';
    signal next_block3_reg      : natural range 0 to BLOCK_COUNT := 0;
    signal next_block12_reg     : natural range 0 to BLOCK_COUNT := 0;
    signal next_block48_reg     : natural range 0 to BLOCK_COUNT := 0;
    signal read_offset_reg      : natural range 0 to BLOCK_SIZE := 0;

    signal ram_addr3_reg        : unsigned(11 downto 0) := (others => '0');
    signal ram_addr12_reg       : unsigned(11 downto 0) := (others => '0');
    signal ram_addr48_reg       : unsigned(11 downto 0) := (others => '0');
    signal stream_bank_reg      : unsigned(1 downto 0) := BANK_SEL_3KHZ;
    signal processing_bank_reg  : unsigned(1 downto 0) := BANK_SEL_3KHZ;

    signal valid_pipe_reg       : std_logic := '0';
    signal start_pipe_reg       : std_logic := '0';
    signal end_pipe_reg         : std_logic := '0';
    signal bank_pipe_reg        : unsigned(1 downto 0) := BANK_SEL_3KHZ;
    signal sample_valid_reg     : std_logic := '0';
    signal block_start_reg      : std_logic := '0';
    signal block_end_reg        : std_logic := '0';
    signal sample_bank_reg      : unsigned(1 downto 0) := BANK_SEL_3KHZ;

    signal core_ready           : std_logic;
    signal core_sample_in       : signed(23 downto 0);
    signal core_power_raw       : unsigned(POWER_WIDTH - 1 downto 0);
    signal core_power_valid     : std_logic;
    signal core_power_bin       : unsigned(5 downto 0);
    signal core_power_last      : std_logic;
    signal core_done            : std_logic;

    signal g_done3_reg          : std_logic := '0';
    signal g_done12_reg         : std_logic := '0';
    signal g_done48_reg         : std_logic := '0';

    signal power3_raw      : unsigned(POWER_WIDTH - 1 downto 0);
    signal power3_valid    : std_logic;
    signal power3_bin      : unsigned(5 downto 0);
    signal power3_last     : std_logic;

    signal power12_raw     : unsigned(POWER_WIDTH - 1 downto 0);
    signal power12_valid   : std_logic;
    signal power12_bin     : unsigned(5 downto 0);
    signal power12_last    : std_logic;

    signal power48_raw     : unsigned(POWER_WIDTH - 1 downto 0);
    signal power48_valid   : std_logic;
    signal power48_bin     : unsigned(5 downto 0);
    signal power48_last    : std_logic;

    --------------------------------------------------------------------------
    -- Per-bank best-bin tracking.
    --
    -- Each bank emits powers sequentially from bin 0 to its last bin. During a
    -- bank block, best*_power/key hold the largest power seen so far. When the
    -- bank asserts POWER_LAST, the final best value becomes that bank's current
    -- candidate for the global note comparison.
    --------------------------------------------------------------------------
    signal best3_power        : unsigned(POWER_WIDTH - 1 downto 0) := (others => '0');
    signal best3_key          : unsigned(NOTE_WIDTH - 1 downto 0) := (others => '0');
    signal best12_power       : unsigned(POWER_WIDTH - 1 downto 0) := (others => '0');
    signal best12_key         : unsigned(NOTE_WIDTH - 1 downto 0) := (others => '0');
    signal best48_power       : unsigned(POWER_WIDTH - 1 downto 0) := (others => '0');
    signal best48_key         : unsigned(NOTE_WIDTH - 1 downto 0) := (others => '0');

    signal candidate3_valid   : std_logic := '0';
    signal candidate3_power   : unsigned(POWER_WIDTH - 1 downto 0) := (others => '0');
    signal candidate3_key     : unsigned(NOTE_WIDTH - 1 downto 0) := (others => '0');
    signal candidate12_valid  : std_logic := '0';
    signal candidate12_power  : unsigned(POWER_WIDTH - 1 downto 0) := (others => '0');
    signal candidate12_key    : unsigned(NOTE_WIDTH - 1 downto 0) := (others => '0');
    signal candidate48_valid  : std_logic := '0';
    signal candidate48_power  : unsigned(POWER_WIDTH - 1 downto 0) := (others => '0');
    signal candidate48_key    : unsigned(NOTE_WIDTH - 1 downto 0) := (others => '0');

    signal note_key_reg       : unsigned(NOTE_WIDTH - 1 downto 0) := (others => '0');
    signal note_valid_reg     : std_logic := '0';

begin

    --------------------------------------------------------------------------
    -- Shared RAM reader and request queue.
    --
    -- G_EN pulses from the preprocessor are one clock wide. Because there is
    -- only one Goertzel core, this wrapper latches one pending request per bank
    -- and services those requests in Bank1/Bank2/Bank3 priority order. Each bank
    -- still receives its own G_DONE pulse after its block has been processed, so
    -- the preprocessor's original per-bank handshake remains unchanged.
    --------------------------------------------------------------------------
    reader_proc : process (sys_clk)
        variable pending3_next     : std_logic;
        variable pending12_next    : std_logic;
        variable pending48_next    : std_logic;
        variable start_selected    : boolean;
        variable selected_bank     : unsigned(1 downto 0);
        variable selected_block    : natural range 0 to BLOCK_COUNT - 1;
    begin
        if rising_edge(sys_clk) then
            if sys_rst = '1' then
                reader_state_reg    <= IDLE;
                request3_pending    <= '0';
                request12_pending   <= '0';
                request48_pending   <= '0';
                next_block3_reg     <= 0;
                next_block12_reg    <= 0;
                next_block48_reg    <= 0;
                read_offset_reg     <= 0;
                ram_addr3_reg       <= (others => '0');
                ram_addr12_reg      <= (others => '0');
                ram_addr48_reg      <= (others => '0');
                stream_bank_reg     <= BANK_SEL_3KHZ;
                processing_bank_reg <= BANK_SEL_3KHZ;
                valid_pipe_reg      <= '0';
                start_pipe_reg      <= '0';
                end_pipe_reg        <= '0';
                bank_pipe_reg       <= BANK_SEL_3KHZ;
                sample_valid_reg    <= '0';
                block_start_reg     <= '0';
                block_end_reg       <= '0';
                sample_bank_reg     <= BANK_SEL_3KHZ;
                g_done3_reg         <= '0';
                g_done12_reg        <= '0';
                g_done48_reg        <= '0';
            else
                sample_valid_reg <= valid_pipe_reg;
                block_start_reg  <= start_pipe_reg;
                block_end_reg    <= end_pipe_reg;
                sample_bank_reg  <= bank_pipe_reg;

                valid_pipe_reg <= '0';
                start_pipe_reg <= '0';
                end_pipe_reg   <= '0';
                g_done3_reg    <= '0';
                g_done12_reg   <= '0';
                g_done48_reg   <= '0';

                pending3_next  := request3_pending;
                pending12_next := request12_pending;
                pending48_next := request48_pending;

                if G_EN3 = '1' then
                    pending3_next := '1';
                end if;

                if G_EN12 = '1' then
                    pending12_next := '1';
                end if;

                if G_EN48 = '1' then
                    pending48_next := '1';
                end if;

                if core_done = '1' then
                    if processing_bank_reg = BANK_SEL_3KHZ then
                        g_done3_reg <= '1';
                    elsif processing_bank_reg = BANK_SEL_12KHZ then
                        g_done12_reg <= '1';
                    else
                        g_done48_reg <= '1';
                    end if;
                end if;

                case reader_state_reg is
                    when IDLE =>
                        read_offset_reg <= 0;
                        start_selected := false;
                        selected_bank  := BANK_SEL_3KHZ;
                        selected_block := 0;

                        if core_ready = '1' then
                            if pending3_next = '1' and next_block3_reg < BLOCK_COUNT then
                                start_selected := true;
                                selected_bank  := BANK_SEL_3KHZ;
                                selected_block := next_block3_reg;
                                pending3_next  := '0';
                                next_block3_reg <= next_block3_reg + 1;
                            elsif pending12_next = '1' and next_block12_reg < BLOCK_COUNT then
                                start_selected := true;
                                selected_bank  := BANK_SEL_12KHZ;
                                selected_block := next_block12_reg;
                                pending12_next := '0';
                                next_block12_reg <= next_block12_reg + 1;
                            elsif pending48_next = '1' and next_block48_reg < BLOCK_COUNT then
                                start_selected := true;
                                selected_bank  := BANK_SEL_48KHZ;
                                selected_block := next_block48_reg;
                                pending48_next := '0';
                                next_block48_reg <= next_block48_reg + 1;
                            end if;

                            if start_selected then
                                if selected_bank = BANK_SEL_3KHZ then
                                    ram_addr3_reg <= ram_addr_for(selected_block, 0);
                                elsif selected_bank = BANK_SEL_12KHZ then
                                    ram_addr12_reg <= ram_addr_for(selected_block, 0);
                                else
                                    ram_addr48_reg <= ram_addr_for(selected_block, 0);
                                end if;

                                stream_bank_reg     <= selected_bank;
                                processing_bank_reg <= selected_bank;
                                bank_pipe_reg       <= selected_bank;
                                valid_pipe_reg      <= '1';
                                start_pipe_reg      <= '1';
                                end_pipe_reg        <= '0';
                                read_offset_reg     <= 1;
                                reader_state_reg    <= STREAM_BLOCK;
                            end if;
                        end if;

                    when STREAM_BLOCK =>
                        if valid_pipe_reg = '1' and end_pipe_reg = '1' then
                            read_offset_reg  <= 0;
                            reader_state_reg <= IDLE;
                        elsif read_offset_reg < BLOCK_SIZE then
                            if stream_bank_reg = BANK_SEL_3KHZ then
                                ram_addr3_reg <= ram_addr_for(next_block3_reg - 1, read_offset_reg);
                            elsif stream_bank_reg = BANK_SEL_12KHZ then
                                ram_addr12_reg <= ram_addr_for(next_block12_reg - 1, read_offset_reg);
                            else
                                ram_addr48_reg <= ram_addr_for(next_block48_reg - 1, read_offset_reg);
                            end if;

                            bank_pipe_reg  <= stream_bank_reg;
                            valid_pipe_reg <= '1';
                            start_pipe_reg <= '0';

                            if read_offset_reg = BLOCK_SIZE - 1 then
                                end_pipe_reg <= '1';
                            else
                                end_pipe_reg <= '0';
                            end if;

                            read_offset_reg <= read_offset_reg + 1;
                        end if;
                end case;

                request3_pending  <= pending3_next;
                request12_pending <= pending12_next;
                request48_pending <= pending48_next;
            end if;
        end if;
    end process reader_proc;

    core_sample_in <= RAM_DATA3 when sample_bank_reg = BANK_SEL_3KHZ else
                      RAM_DATA12 when sample_bank_reg = BANK_SEL_12KHZ else
                      RAM_DATA48;

    shared_core_inst : entity work.goertzel_shared_multi_bank
        generic map (
            BANK1_COEFF_FILE => BANK1_COEFF_FILE,
            BANK2_COEFF_FILE => BANK2_COEFF_FILE,
            BANK3_COEFF_FILE => BANK3_COEFF_FILE
        )
        port map (
            clk             => sys_clk,
            rst             => sys_rst,
            bank_select_in  => sample_bank_reg,
            sample_ready    => core_ready,
            sample_in       => core_sample_in,
            sample_valid_in => sample_valid_reg,
            block_start_in  => block_start_reg,
            block_end_in    => block_end_reg,
            power_out       => core_power_raw,
            power_valid_out => core_power_valid,
            power_bin_index => core_power_bin,
            power_last_out  => core_power_last,
            block_done_out  => core_done
        );

    --------------------------------------------------------------------------
    -- Decode the shared core's raw power stream back into per-bank streams for
    -- the existing note-selection logic. processing_bank_reg remains stable for
    -- the bank currently being evaluated, so these valid strobes identify which
    -- running best-power register should consume the core result.
    --------------------------------------------------------------------------
    power3_raw    <= core_power_raw;
    power3_valid  <= core_power_valid when processing_bank_reg = BANK_SEL_3KHZ else '0';
    power3_bin    <= core_power_bin;
    power3_last   <= core_power_last when processing_bank_reg = BANK_SEL_3KHZ else '0';

    power12_raw   <= core_power_raw;
    power12_valid <= core_power_valid when processing_bank_reg = BANK_SEL_12KHZ else '0';
    power12_bin   <= core_power_bin;
    power12_last  <= core_power_last when processing_bank_reg = BANK_SEL_12KHZ else '0';

    power48_raw   <= core_power_raw;
    power48_valid <= core_power_valid when processing_bank_reg = BANK_SEL_48KHZ else '0';
    power48_bin   <= core_power_bin;
    power48_last  <= core_power_last when processing_bank_reg = BANK_SEL_48KHZ else '0';

    note_select_proc : process (sys_clk)
        variable next_best3_power       : unsigned(POWER_WIDTH - 1 downto 0);
        variable next_best3_key         : unsigned(NOTE_WIDTH - 1 downto 0);
        variable next_best12_power      : unsigned(POWER_WIDTH - 1 downto 0);
        variable next_best12_key        : unsigned(NOTE_WIDTH - 1 downto 0);
        variable next_best48_power      : unsigned(POWER_WIDTH - 1 downto 0);
        variable next_best48_key        : unsigned(NOTE_WIDTH - 1 downto 0);

        variable next_candidate3_valid  : std_logic;
        variable next_candidate3_power  : unsigned(POWER_WIDTH - 1 downto 0);
        variable next_candidate3_key    : unsigned(NOTE_WIDTH - 1 downto 0);
        variable next_candidate12_valid : std_logic;
        variable next_candidate12_power : unsigned(POWER_WIDTH - 1 downto 0);
        variable next_candidate12_key   : unsigned(NOTE_WIDTH - 1 downto 0);
        variable next_candidate48_valid : std_logic;
        variable next_candidate48_power : unsigned(POWER_WIDTH - 1 downto 0);
        variable next_candidate48_key   : unsigned(NOTE_WIDTH - 1 downto 0);

        variable winner_power           : unsigned(POWER_WIDTH - 1 downto 0);
        variable winner_key             : unsigned(NOTE_WIDTH - 1 downto 0);
    begin
        if rising_edge(sys_clk) then
            if sys_rst = '1' then
                best3_power       <= (others => '0');
                best3_key         <= (others => '0');
                best12_power      <= (others => '0');
                best12_key        <= (others => '0');
                best48_power      <= (others => '0');
                best48_key        <= (others => '0');
                candidate3_valid  <= '0';
                candidate3_power  <= (others => '0');
                candidate3_key    <= (others => '0');
                candidate12_valid <= '0';
                candidate12_power <= (others => '0');
                candidate12_key   <= (others => '0');
                candidate48_valid <= '0';
                candidate48_power <= (others => '0');
                candidate48_key   <= (others => '0');
                note_key_reg      <= (others => '0');
                note_valid_reg    <= '0';
            else
                note_valid_reg <= '0';

                next_best3_power       := best3_power;
                next_best3_key         := best3_key;
                next_best12_power      := best12_power;
                next_best12_key        := best12_key;
                next_best48_power      := best48_power;
                next_best48_key        := best48_key;

                next_candidate3_valid  := candidate3_valid;
                next_candidate3_power  := candidate3_power;
                next_candidate3_key    := candidate3_key;
                next_candidate12_valid := candidate12_valid;
                next_candidate12_power := candidate12_power;
                next_candidate12_key   := candidate12_key;
                next_candidate48_valid := candidate48_valid;
                next_candidate48_power := candidate48_power;
                next_candidate48_key   := candidate48_key;

                ------------------------------------------------------------------
                -- Bank1/3 kHz max tracking. Bin 0 starts a new bank result, so it
                -- always initializes the running best value. Later bins update the
                -- best value only when their power is strictly greater, preserving
                -- the lower key on exact ties.
                ------------------------------------------------------------------
                if power3_valid = '1' then
                    if power3_bin = to_unsigned(0, power3_bin'length) then
                        next_best3_power := power3_raw;
                        next_best3_key   := bin_to_key(BANK1_FIRST_KEY, power3_bin);
                    elsif power3_raw > best3_power then
                        next_best3_power := power3_raw;
                        next_best3_key   := bin_to_key(BANK1_FIRST_KEY, power3_bin);
                    end if;

                    if power3_last = '1' then
                        next_candidate3_valid := '1';
                        next_candidate3_power := next_best3_power;
                        next_candidate3_key   := next_best3_key;
                    end if;
                end if;

                ------------------------------------------------------------------
                -- Bank2/12 kHz uses the same max-selection policy, with local
                -- bins mapped into workbook keys 25 through 48.
                ------------------------------------------------------------------
                if power12_valid = '1' then
                    if power12_bin = to_unsigned(0, power12_bin'length) then
                        next_best12_power := power12_raw;
                        next_best12_key   := bin_to_key(BANK2_FIRST_KEY, power12_bin);
                    elsif power12_raw > best12_power then
                        next_best12_power := power12_raw;
                        next_best12_key   := bin_to_key(BANK2_FIRST_KEY, power12_bin);
                    end if;

                    if power12_last = '1' then
                        next_candidate12_valid := '1';
                        next_candidate12_power := next_best12_power;
                        next_candidate12_key   := next_best12_key;
                    end if;
                end if;

                ------------------------------------------------------------------
                -- Bank3/48 kHz covers the top forty keys. The internal bin range is
                -- larger, but the candidate latch is identical to the other banks.
                ------------------------------------------------------------------
                if power48_valid = '1' then
                    if power48_bin = to_unsigned(0, power48_bin'length) then
                        next_best48_power := power48_raw;
                        next_best48_key   := bin_to_key(BANK3_FIRST_KEY, power48_bin);
                    elsif power48_raw > best48_power then
                        next_best48_power := power48_raw;
                        next_best48_key   := bin_to_key(BANK3_FIRST_KEY, power48_bin);
                    end if;

                    if power48_last = '1' then
                        next_candidate48_valid := '1';
                        next_candidate48_power := next_best48_power;
                        next_candidate48_key   := next_best48_key;
                    end if;
                end if;

                ------------------------------------------------------------------
                -- Global note decision.
                --
                -- The three banks finish blocks at different rates. Each bank keeps
                -- only its latest completed candidate while waiting for the other
                -- two banks. Once every bank has a fresh candidate, compare the raw
                -- powers directly and emit one NOTE_VALID pulse. No threshold is
                -- used yet; the strongest candidate always becomes NOTE_KEY.
                ------------------------------------------------------------------
                if next_candidate3_valid = '1' and
                   next_candidate12_valid = '1' and
                   next_candidate48_valid = '1' then

                    winner_power := next_candidate3_power;
                    winner_key   := next_candidate3_key;

                    if next_candidate12_power > winner_power then
                        winner_power := next_candidate12_power;
                        winner_key   := next_candidate12_key;
                    end if;

                    if next_candidate48_power > winner_power then
                        winner_power := next_candidate48_power;
                        winner_key   := next_candidate48_key;
                    end if;

                    -- synthesis translate_off
                    report "HW_NOTE_DECISION key=" &
                           integer'image(to_integer(winner_key)) &
                           " power=0x" &
                           unsigned_to_hex(winner_power)
                           severity note;
                    -- synthesis translate_on

                    note_key_reg  <= winner_key;
                    note_valid_reg <= '1';

                    next_candidate3_valid  := '0';
                    next_candidate12_valid := '0';
                    next_candidate48_valid := '0';
                end if;

                best3_power       <= next_best3_power;
                best3_key         <= next_best3_key;
                best12_power      <= next_best12_power;
                best12_key        <= next_best12_key;
                best48_power      <= next_best48_power;
                best48_key        <= next_best48_key;
                candidate3_valid  <= next_candidate3_valid;
                candidate3_power  <= next_candidate3_power;
                candidate3_key    <= next_candidate3_key;
                candidate12_valid <= next_candidate12_valid;
                candidate12_power <= next_candidate12_power;
                candidate12_key   <= next_candidate12_key;
                candidate48_valid <= next_candidate48_valid;
                candidate48_power <= next_candidate48_power;
                candidate48_key   <= next_candidate48_key;
            end if;
        end if;
    end process note_select_proc;

    NOTE_KEY   <= note_key_reg;
    NOTE_VALID <= note_valid_reg;
    RAM_ADDR3  <= ram_addr3_reg;
    RAM_ADDR12 <= ram_addr12_reg;
    RAM_ADDR48 <= ram_addr48_reg;
    G_DONE3    <= g_done3_reg;
    G_DONE12   <= g_done12_reg;
    G_DONE48   <= g_done48_reg;

end architecture rtl;
