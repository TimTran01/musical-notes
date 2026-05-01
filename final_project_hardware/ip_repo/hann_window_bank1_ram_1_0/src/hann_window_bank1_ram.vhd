----------------------------------------------------------------------------------
-- Module Name: hann_window_bank1_ram
--
-- Description:
--   Captures bank-1 Hann-windowed samples into a 4096 x 24-bit RAM.
--
--   The input stream is the 48 kHz, signed 24-bit output from hann_window_4096.
--   The Hann IP performs the 48-bit multiply internally, then truncates the
--   Q24.23 product back to an ADC-like signed 24-bit integer before it reaches
--   this RAM. Bank 1 therefore stores the post-window integer samples, not the
--   full 48-bit fixed-point products.
--
--   Bank 1 stores a 3 kHz view of that stream by writing the first valid sample
--   after frame_start_in and then one out of every 16 valid input samples.
--
--   This RAM stores time-domain samples only. Piano-key/frequency selection is
--   intentionally left to the later detector/Goertzel bank logic.
--
--   Once 4096 samples have been captured, capture_done is asserted and writes
--   stop until reset. The debug read port is synchronous and intended for
--   simulation and later downstream RTL validation.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hann_window_bank1_ram is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        sample_in       : in  signed(23 downto 0);
        sample_valid_in : in  std_logic;
        frame_start_in  : in  std_logic;
        read_addr       : in  unsigned(11 downto 0);
        read_data       : out signed(23 downto 0);
        capture_done    : out std_logic;
        write_count     : out unsigned(12 downto 0)
    );
end entity hann_window_bank1_ram;

architecture rtl of hann_window_bank1_ram is

    --------------------------------------------------------------------------
    -- RAM/capture sizing.
    --
    -- The Hann block emits one valid sample at 48 kHz. Bank 1 needs a 3 kHz
    -- analysis stream, so the write logic keeps one valid sample and skips the
    -- next 15 valid samples. 48 kHz / 16 = 3 kHz.
    --
    -- A 4096-entry RAM needs 12 address bits. write_count is 13 bits so it can
    -- represent the full count value 4096 after the last write completes.
    --------------------------------------------------------------------------
    constant RAM_DEPTH        : natural := 4096;
    constant ADDR_WIDTH       : natural := 12;
    -- Data width matches the truncated Hann output. The discarded fractional
    -- bits are not stored here; if a later detector needs more precision, the
    -- Hann output/RAM width would need to be widened together.
    constant DATA_WIDTH       : natural := 24;
    constant DECIMATION_RATIO : natural := 16;

    type ram_t is array (0 to RAM_DEPTH - 1) of signed(DATA_WIDTH - 1 downto 0);

    signal ram : ram_t := (others => (others => '0'));

    --------------------------------------------------------------------------
    -- Block RAM hint.
    --
    -- 4096 x 24 bits is large enough that it should map into BRAM resources.
    -- The attribute is a synthesis hint; simulation still uses this VHDL array.
    --------------------------------------------------------------------------
    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";

    --------------------------------------------------------------------------
    -- Capture state.
    --
    -- read_data_reg:
    --   Registered debug read output. read_addr is not part of the write/capture
    --   path; it should come from later detector/debug logic that wants to read
    --   a stored RAM address.
    --
    -- write_addr_counter:
    --   Address for the next decimated sample write. It advances only when a
    --   sample is actually stored.
    --
    -- capture_active_reg:
    --   Low until frame_start_in arms this RAM for a one-note capture. This
    --   prevents random pre-frame samples from entering the RAM.
    --
    -- capture_done_reg:
    --   Asserted after address 4095 is written. Once done is high, all writes
    --   are blocked until reset so the completed note window is held stable.
    --
    -- decimation_skip_reg:
    --   Counts how many valid 48 kHz Hann samples still need to be ignored
    --   before the next 3 kHz RAM write. After each write it is loaded with 15.
    --------------------------------------------------------------------------
    signal read_data_reg       : signed(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal write_addr_counter  : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal write_count_reg     : unsigned(12 downto 0) := (others => '0');
    signal capture_active_reg  : std_logic := '0';
    signal capture_done_reg    : std_logic := '0';
    signal decimation_skip_reg : natural range 0 to DECIMATION_RATIO - 1 := 0;

begin

    ram_proc : process (clk)
        variable should_write : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ------------------------------------------------------------------
                -- Reset starts a new one-note capture window. RAM contents are not
                -- explicitly cleared because write_count/capture_done define which
                -- entries belong to the current capture.
                ------------------------------------------------------------------
                read_data_reg       <= (others => '0');
                write_addr_counter  <= (others => '0');
                write_count_reg     <= (others => '0');
                capture_active_reg  <= '0';
                capture_done_reg    <= '0';
                decimation_skip_reg <= 0;
            else
                ------------------------------------------------------------------
                -- Synchronous debug read.
                --
                -- read_data reflects the RAM word addressed by read_addr after one
                -- clock edge. This read port is independent of the capture/write
                -- side so future detector logic can walk through addresses 0..4095.
                ------------------------------------------------------------------
                read_data_reg <= ram(to_integer(read_addr));
                should_write := false;

                if capture_done_reg = '0' then
                    if capture_active_reg = '0' then
                        ----------------------------------------------------------
                        -- Arm capture on frame_start_in. If frame_start and valid
                        -- arrive together, store that sample as address 0. If
                        -- frame_start arrives by itself, the next valid sample
                        -- becomes address 0.
                        ----------------------------------------------------------
                        if frame_start_in = '1' then
                            capture_active_reg  <= '1';
                            decimation_skip_reg <= 0;

                            if sample_valid_in = '1' then
                                should_write := true;
                            end if;
                        end if;
                    elsif sample_valid_in = '1' then
                        ----------------------------------------------------------
                        -- Decimation runs only on valid Hann samples, not raw
                        -- clocks. A skip count of zero means this valid sample is
                        -- the next 3 kHz sample and should be stored.
                        ----------------------------------------------------------
                        if decimation_skip_reg = 0 then
                            should_write := true;
                        else
                            decimation_skip_reg <= decimation_skip_reg - 1;
                        end if;
                    end if;
                end if;

                if should_write then
                    ------------------------------------------------------------------
                    -- Store the selected 24-bit Hann sample and advance to the next
                    -- RAM address.
                    --
                    -- No additional scaling is done in this RAM. sample_in already
                    -- equals the Hann IP's truncated integer result:
                    --
                    --   sample_in = arithmetic_shift_right(
                    --                   sample_24b * coefficient_Q1_23, 23)
                    --
                    -- Keeping the RAM passive makes the data contract clear: the
                    -- window block owns fixed-point scaling, and this block only
                    -- decimates and stores ADC-width signed samples.
                    ------------------------------------------------------------------
                    ram(to_integer(write_addr_counter)) <= sample_in;
                    write_count_reg <= write_count_reg + 1;

                    if write_addr_counter = to_unsigned(RAM_DEPTH - 1, ADDR_WIDTH) then
                        --------------------------------------------------------------
                        -- Last address written. Freeze the RAM contents and report
                        -- completion. No circular overwrite is used for single-note
                        -- capture.
                        --------------------------------------------------------------
                        capture_done_reg    <= '1';
                        capture_active_reg  <= '0';
                        decimation_skip_reg <= 0;
                    else
                        write_addr_counter  <= write_addr_counter + 1;
                        decimation_skip_reg <= DECIMATION_RATIO - 1;
                    end if;
                end if;
            end if;
        end if;
    end process ram_proc;

    read_data    <= read_data_reg;
    capture_done <= capture_done_reg;
    write_count  <= write_count_reg;

end architecture rtl;
