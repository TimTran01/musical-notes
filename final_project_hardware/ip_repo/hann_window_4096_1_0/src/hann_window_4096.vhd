----------------------------------------------------------------------------------
-- Module Name: hann_window_4096
--
-- Description:
--   Applies a 4096-point Hann window to signed 24-bit ADC samples.
--
--   The coefficient ROM is generated from the same formula used in the Excel
--   reference model:
--
--     w[n] = 0.5 * (1 - cos(2*pi*n/(4096 - 1)))
--
--   Coefficients are stored as unsigned Q1.23 fixed-point values. The largest
--   coefficient is close to 1.0 and is encoded near 0x7FFFFF. The input sample
--   is signed 24-bit. Multiplying these two 24-bit operands produces an
--   internal signed 48-bit Q24.23 fixed-point product.
--
--   The public output is signed 24-bit. The 48-bit product is arithmetically
--   shifted right by 23 bits, discarding the fractional Q1.23 coefficient bits.
--   This is intentional truncation, not rounding. It keeps the hardware simple
--   and makes the output look like ADC-width integer data again for the RAM and
--   later Goertzel blocks.
--
-- Timing:
--   sample_valid_out is asserted one clock after sample_valid_in. sample_out,
--   sample_index_out, and frame_start_out are delayed by the same amount, so
--   all output signals remain aligned.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity hann_window_4096 is
    generic (
        -- Python-generated coefficient file. Each line contains one unsigned
        -- 24-bit Q1.23 coefficient as six hexadecimal digits.
        MEM_FILE : string := "hann_window.mem"
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        sample_in        : in  signed(23 downto 0);
        sample_valid_in  : in  std_logic;
        sample_index_in  : in  unsigned(11 downto 0);
        frame_start_in   : in  std_logic;
        sample_out       : out signed(23 downto 0);
        sample_valid_out : out std_logic;
        sample_index_out : out unsigned(11 downto 0);
        frame_start_out  : out std_logic
    );
end entity hann_window_4096;

architecture rtl of hann_window_4096 is

    --------------------------------------------------------------------------
    -- Window and fixed-point sizing.
    --
    -- A 12-bit sample index selects one of 4096 Hann coefficients. The 24-bit
    -- coefficient width matches the ADC sample width, so the raw product is
    -- exactly 48 bits. The public output width stays at 24 bits so downstream
    -- RAM and detector blocks can keep an ADC-like data path.
    --------------------------------------------------------------------------
    constant WINDOW_LENGTH : natural := 4096;
    constant INDEX_WIDTH   : natural := 12;
    constant SAMPLE_WIDTH  : natural := 24;
    constant PRODUCT_WIDTH : natural := 48;

    -- The coefficient format is Q1.23: one integer/sign-position bit and
    -- twenty-three fractional bits. After multiplication, those 23 fractional
    -- bits are still present in the low side of the 48-bit product. Shifting
    -- right by this amount converts the product back to a 24-bit integer scale.
    constant FRACTION_BITS : natural := 23;

    --------------------------------------------------------------------------
    -- Coefficient ROM storage.
    --
    -- Coefficients are stored as std_logic_vector because the memory file is a
    -- raw hexadecimal bit pattern. A coefficient is converted to signed only at
    -- the multiplier input. The generated values are limited to 0x7FFFFF, so
    -- that conversion always represents a non-negative multiplier.
    --------------------------------------------------------------------------
    type coeff_rom_t is array (0 to WINDOW_LENGTH - 1) of std_logic_vector(SAMPLE_WIDTH - 1 downto 0);

    --------------------------------------------------------------------------
    -- ROM initialization function.
    --
    -- The function reads one hex coefficient per line from MEM_FILE. Production
    -- data should contain all 4096 coefficients. Missing entries remain zero so
    -- simulation failures are easy to diagnose without undefined values.
    --------------------------------------------------------------------------
    impure function init_coeff_rom(file_name : string) return coeff_rom_t is
        file coeff_file       : text open read_mode is file_name;
        variable rom_data     : coeff_rom_t := (others => (others => '0'));
        variable current_line : line;
        variable coeff_word   : std_logic_vector(SAMPLE_WIDTH - 1 downto 0);
        variable read_ok      : boolean;
        variable coeff_index  : natural := 0;
    begin
        while (not endfile(coeff_file)) and (coeff_index < WINDOW_LENGTH) loop
            readline(coeff_file, current_line);
            hread(current_line, coeff_word, read_ok);

            assert read_ok
                report "hann_window_4096: invalid hexadecimal coefficient in " &
                       file_name & " at index " & integer'image(coeff_index)
                severity failure;

            rom_data(coeff_index) := coeff_word;
            coeff_index := coeff_index + 1;
        end loop;

        assert coeff_index = WINDOW_LENGTH
            report "hann_window_4096: " & file_name &
                   " contains fewer than 4096 coefficients; remaining entries are zero"
            severity warning;

        assert endfile(coeff_file)
            report "hann_window_4096: " & file_name &
                   " contains more than 4096 coefficients; extra entries are ignored"
            severity warning;

        return rom_data;
    end function init_coeff_rom;

    signal coeff_rom : coeff_rom_t := init_coeff_rom(MEM_FILE);

    attribute rom_style : string;
    attribute rom_style of coeff_rom : signal is "block";

    --------------------------------------------------------------------------
    -- Pipeline stage 1.
    --
    -- On a valid input sample, this stage captures the ADC sample, the selected
    -- Hann coefficient, and the metadata that must travel with the sample.
    --------------------------------------------------------------------------
    signal sample_stage1      : signed(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
    signal coeff_stage1       : signed(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
    signal valid_stage1       : std_logic := '0';
    signal index_stage1       : unsigned(INDEX_WIDTH - 1 downto 0) := (others => '0');
    signal frame_start_stage1 : std_logic := '0';

    --------------------------------------------------------------------------
    -- Registered outputs.
    --
    -- The multiplier result is registered so downstream DSP logic sees a stable
    -- truncated 24-bit sample only when sample_valid_out is asserted.
    --------------------------------------------------------------------------
    signal sample_out_reg       : signed(SAMPLE_WIDTH - 1 downto 0) := (others => '0');
    signal sample_valid_out_reg : std_logic := '0';
    signal sample_index_out_reg : unsigned(INDEX_WIDTH - 1 downto 0) := (others => '0');
    signal frame_start_out_reg  : std_logic := '0';

begin

    --------------------------------------------------------------------------
    -- Hann multiply pipeline.
    --
    -- The first part of the process captures the current input and coefficient.
    -- The second part multiplies the previous cycle's captured values. Because
    -- signal assignments update after the clock edge, sample_out_reg uses the
    -- stage-1 values from the previous clock. This creates a clean one-clock
    -- latency from input valid to output valid.
    --------------------------------------------------------------------------
    window_proc : process (clk)
        variable product_48 : signed(PRODUCT_WIDTH - 1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sample_stage1        <= (others => '0');
                coeff_stage1         <= (others => '0');
                valid_stage1         <= '0';
                index_stage1         <= (others => '0');
                frame_start_stage1   <= '0';
                sample_out_reg       <= (others => '0');
                sample_valid_out_reg <= '0';
                sample_index_out_reg <= (others => '0');
                frame_start_out_reg  <= '0';
            else
                ------------------------------------------------------------------
                -- Full-precision fixed-point multiply.
                --
                -- sample_stage1 is a signed 24-bit integer ADC value.
                -- coeff_stage1 is a non-negative Q1.23 Hann coefficient.
                -- The product is therefore Q24.23 in a signed 48-bit container:
                --   upper bits  = signed integer magnitude
                --   lower bits  = fractional contribution from the coefficient
                ------------------------------------------------------------------
                product_48 := sample_stage1 * coeff_stage1;

                ------------------------------------------------------------------
                -- Truncate the Q24.23 product back to a signed 24-bit sample.
                --
                -- shift_right() on a signed value performs an arithmetic shift,
                -- so negative samples keep their sign while the 23 fractional
                -- bits are discarded. This is equivalent to dividing by 2^23 and
                -- keeping only the integer result. No rounding is added here.
                --
                -- After the shift, resize() keeps the ADC-width result. For valid
                -- Hann coefficients in the range 0.0 to just under 1.0, the
                -- shifted value remains in the original signed 24-bit sample
                -- range, so resize mainly removes redundant sign-extension bits.
                ------------------------------------------------------------------
                sample_out_reg <= resize(
                    shift_right(product_48, FRACTION_BITS),
                    SAMPLE_WIDTH
                );
                sample_valid_out_reg <= valid_stage1;
                sample_index_out_reg <= index_stage1;
                frame_start_out_reg  <= frame_start_stage1;

                if sample_valid_in = '1' then
                    sample_stage1      <= sample_in;
                    coeff_stage1       <= signed(coeff_rom(to_integer(sample_index_in)));
                    index_stage1       <= sample_index_in;
                    frame_start_stage1 <= frame_start_in;
                end if;

                valid_stage1 <= sample_valid_in;
            end if;
        end if;
    end process window_proc;

    sample_out       <= sample_out_reg;
    sample_valid_out <= sample_valid_out_reg;
    sample_index_out <= sample_index_out_reg;
    frame_start_out  <= frame_start_out_reg;

end architecture rtl;
