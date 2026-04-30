----------------------------------------------------------------------------------
-- Module Name: adc_sample_48khz_sampler
--
-- Description:
--   IP-ready wrapper around adc_sample_rom. This block reads one 24-bit ADC
--   sample from the ROM at an average rate of 48 kHz and presents that sample
--   with a one-clock sample_valid pulse.
--
--   The intended block diagram clock is the Zynq FCLK_CLK0 configured to
--   50 MHz. Since 50,000,000 / 48,000 is not an integer, the sampler uses a
--   fractional accumulator. That accumulator alternates between 1041-clock and
--   1042-clock sample intervals so the long-term average is exactly 48 kHz.
--
--   The ROM has a synchronous read. Therefore sample_valid, sample_index, and
--   frame_start are registered on the same clock edge that the ROM output
--   sample becomes valid.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adc_sample_48khz_sampler is
    generic (
        CLK_FREQ_HZ    : positive := 50_000_000;
        SAMPLE_RATE_HZ : positive := 48_000;
        MEM_FILE       : string   := "adc_samples.mem"
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        enable       : in  std_logic;
        sample       : out signed(23 downto 0);
        sample_valid : out std_logic;
        sample_index : out unsigned(11 downto 0);
        frame_start  : out std_logic
    );
end entity adc_sample_48khz_sampler;

architecture rtl of adc_sample_48khz_sampler is

    --------------------------------------------------------------------------
    -- ROM/sample sizing constants.
    --
    -- The ROM stores one 4096-sample frame. A 12-bit counter naturally wraps
    -- from 4095 back to 0 when the sample frame repeats.
    --
    -- These samples are time-domain ADC values. Piano-key/frequency selection
    -- happens later in detector banks; this block only replays a sampled note
    -- waveform at the requested sample rate.
    --------------------------------------------------------------------------
    constant ROM_DEPTH    : natural := 4096;
    constant ADDR_WIDTH   : natural := 12;
    constant SAMPLE_WIDTH : natural := 24;

    --------------------------------------------------------------------------
    -- Fractional timing accumulator.
    --
    -- phase_accumulator represents accumulated sample-rate phase in units of
    -- CLK_FREQ_HZ. Every enabled clock adds SAMPLE_RATE_HZ. When the addition
    -- crosses CLK_FREQ_HZ, one sample period has elapsed and the accumulator
    -- wraps by subtracting CLK_FREQ_HZ.
    --
    -- This is the digital equivalent of a fractional clock divider. It avoids
    -- needing a separate 48 kHz clock domain and keeps downstream sample-valid
    -- pulses synchronous to the 50 MHz processing clock.
    --------------------------------------------------------------------------
    signal phase_accumulator : natural range 0 to CLK_FREQ_HZ - 1 := 0;
    signal sample_tick       : std_logic;

    --------------------------------------------------------------------------
    -- ROM request/address state.
    --
    -- rom_addr_counter is the next ROM address to request. It advances only on
    -- sample_tick, so the ROM is read once per 48 kHz sample event.
    --
    -- The same counter value is later exported as sample_index_reg. Downstream
    -- blocks use that index to align other per-sample metadata, such as Hann
    -- coefficients, with the ADC sample.
    --------------------------------------------------------------------------
    signal rom_addr_counter : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal rom_sample       : signed(SAMPLE_WIDTH - 1 downto 0);

    --------------------------------------------------------------------------
    -- Output timing state.
    --
    -- These registers update on sample_tick, the same clock edge on which the
    -- ROM produces the requested sample. This keeps the sample, index, valid
    -- flag, and frame_start pulse aligned for downstream processing.
    --
    -- frame_start is a one-clock marker for sample index 0. Later capture logic
    -- can use it to start a new one-note analysis window.
    --------------------------------------------------------------------------
    signal sample_valid_reg : std_logic := '0';
    signal sample_index_reg : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal frame_start_reg  : std_logic := '0';

begin

    --------------------------------------------------------------------------
    -- Generic sanity check.
    --
    -- The accumulator assumes at most one sample event can occur per input
    -- clock. That is true for the intended 50 MHz / 48 kHz configuration and
    -- should remain true for later generic overrides.
    --------------------------------------------------------------------------
    assert SAMPLE_RATE_HZ <= CLK_FREQ_HZ
        report "adc_sample_48khz_sampler: SAMPLE_RATE_HZ must be less than or equal to CLK_FREQ_HZ"
        severity failure;

    --------------------------------------------------------------------------
    -- Generate the next 48 kHz sample request.
    --
    -- This is combinational so adc_sample_rom sees en='1' on the same rising
    -- edge that the accumulator crosses the sample boundary.
    --
    -- sample_tick is not a clock. It is a one-cycle clock-enable pulse inside
    -- the 50 MHz domain, which keeps the design single-clock and easier to
    -- connect in the block diagram.
    --------------------------------------------------------------------------
    sample_tick <= '1' when (enable = '1') and
                            (phase_accumulator + SAMPLE_RATE_HZ >= CLK_FREQ_HZ)
                   else '0';

    --------------------------------------------------------------------------
    -- Sample ROM.
    --
    -- The ROM output updates on the rising edge when sample_tick is asserted.
    -- The address is the current rom_addr_counter value before it advances to
    -- the next sample.
    --------------------------------------------------------------------------
    sample_rom_inst : entity work.adc_sample_rom
        generic map (
            MEM_FILE => MEM_FILE
        )
        port map (
            clk    => clk,
            en     => sample_tick,
            addr   => rom_addr_counter,
            sample => rom_sample
        );

    --------------------------------------------------------------------------
    -- Fractional rate generator and ROM address control.
    --
    -- Reset restarts the playback frame at sample 0. Disabling the block pauses
    -- both phase and address state so sampling resumes from the same position.
    --
    -- On every enabled 50 MHz cycle, next_phase predicts the accumulator value
    -- after adding one 48 kHz step. If that addition crosses CLK_FREQ_HZ,
    -- sample_tick is high, the ROM address advances, and the extra phase is
    -- kept by subtracting CLK_FREQ_HZ. That retained phase is what creates the
    -- alternating 1041/1042-cycle spacing.
    --------------------------------------------------------------------------
    sampler_proc : process (clk)
        variable next_phase : natural range 0 to CLK_FREQ_HZ + SAMPLE_RATE_HZ;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                phase_accumulator <= 0;
                rom_addr_counter  <= (others => '0');
                sample_valid_reg  <= '0';
                sample_index_reg  <= (others => '0');
                frame_start_reg   <= '0';
            elsif enable = '1' then
                next_phase := phase_accumulator + SAMPLE_RATE_HZ;

                -- Valid and frame_start are pulses, so their default value each
                -- enabled cycle is low unless a sample boundary occurs below.
                sample_valid_reg <= sample_tick;
                frame_start_reg  <= '0';

                if sample_tick = '1' then
                    -- A sample boundary occurred. Keep the fractional remainder
                    -- for the next interval and report the address that was just
                    -- requested from the synchronous ROM.
                    phase_accumulator <= next_phase - CLK_FREQ_HZ;
                    sample_index_reg  <= rom_addr_counter;

                    if rom_addr_counter = to_unsigned(0, ADDR_WIDTH) then
                        frame_start_reg <= '1';
                    end if;

                    if rom_addr_counter = to_unsigned(ROM_DEPTH - 1, ADDR_WIDTH) then
                        -- End of the 4096-sample note frame. Wrap to address 0
                        -- so the generated ADC sample memory repeats cleanly.
                        rom_addr_counter <= (others => '0');
                    else
                        rom_addr_counter <= rom_addr_counter + 1;
                    end if;
                else
                    -- No sample produced this clock; only accumulated phase moves.
                    phase_accumulator <= next_phase;
                end if;
            else
                -- Pause output pulses while preserving phase/address state. This
                -- lets capture resume from the same point if enable is reasserted.
                sample_valid_reg <= '0';
                frame_start_reg  <= '0';
            end if;
        end if;
    end process sampler_proc;

    sample       <= rom_sample;
    sample_valid <= sample_valid_reg;
    sample_index <= sample_index_reg;
    frame_start  <= frame_start_reg;

end architecture rtl;
