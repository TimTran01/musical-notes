----------------------------------------------------------------------------------
-- Module Name: DataProcessorDatapath
--
-- Description:
--   Datapath for the 3 kHz, 12 kHz, and 48 kHz preprocessing banks.
--
--   The datapath instantiates clk_divider, keeps an independent 12-bit sample
--   address counter for each bank, captures the incoming 24-bit sample when the
--   controller asserts f_en_data*, and multiplies that sample by the matching
--   Hann coefficient. The upper 24 bits of the registered 48-bit product are
--   written into the corresponding RAM bank.
--
-- Block timing:
--   The low seven address bits define the 128-sample block consumed by the
--   Goertzel engine. f_done_* asserts whenever those bits equal 127 so the
--   controller can start the matching Goertzel bank after the final sample of a
--   block has been written.
--
-- Reset behavior:
--   rst clears the bank counters, captured samples, and multiply/scale pipeline
--   registers.
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity DataProcessorDatapath is
Port ( 
    -- System signals
    clk     :   in std_logic;
    rst     :   in std_logic;
    
    -- External input data signals
    sample      :   in std_logic_vector(23 downto 0);
    
    hann0       :   in std_logic_vector(23 downto 0);
    hann1       :   in std_logic_vector(23 downto 0);
    hann2       :   in std_logic_vector(23 downto 0);
    hann_addr0  :   out std_logic_vector(11 downto 0);
    hann_addr1  :   out std_logic_vector(11 downto 0);
    hann_addr2  :   out std_logic_vector(11 downto 0);
    
    ram_addr3   :   out std_logic_vector(11 downto 0);
    ram_addr12  :   out std_logic_vector(11 downto 0);
    ram_addr48  :   out std_logic_vector(11 downto 0);
    ram_data3   :   out std_logic_vector(23 downto 0);
    ram_data12  :   out std_logic_vector(23 downto 0);
    ram_data48  :   out std_logic_vector(23 downto 0);
    
    -- Controller interface
    f_en_cnt3   :   in std_logic;
    f_en_data3  :   in std_logic;
    clk3kHz     :   out std_logic;
    f_done_3    :   out std_logic;
    
    f_en_cnt12  :   in std_logic;
    f_en_data12 :   in std_logic;
    clk12kHz    :   out std_logic;
    f_done_12   :   out std_logic;
    
    f_en_cnt48  :   in std_logic;
    f_en_data48 :   in std_logic;
    clk48kHz    :   out std_logic;
    f_done_48   :   out std_logic 
    
);
end DataProcessorDatapath;

architecture arch of DataProcessorDatapath is
-- clock divider
signal clk3, clk12, clk48 : std_logic := '0';

-- counter signals
constant sample_size : integer := 7;
constant total_sample : integer := 12;
constant data_width : integer := 24;

signal r_cnt3, r_cnt12, r_cnt48 : unsigned(total_sample - 1 downto 0) := (others => '0');
signal product3, product12, product48 : signed((data_width * 2) - 1 downto 0);


begin
cnt_div: entity work.clk_divider(arch)
port map(
        clk_in  => clk,        -- 50 MHz input
        reset   => rst,       -- Asynchronous reset
        clk_out_3 => clk3,      -- 3 kHz output
        clk_out_12 => clk12,     -- 12 kHz output
        clk_out_48 => clk48     -- 48 kHz output
);

clk3kHz <= clk3;
clk12kHz <= clk12;
clk48kHz <= clk48;


p_count_3kHz: process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            r_cnt3 <= (others => '0');
        elsif f_en_cnt3 = '1' then
            r_cnt3 <= r_cnt3 + 1;  -- increment counter
        end if;
    end if;
end process;

f_done_3 <= '1' when r_cnt3(6 downto 0) = "1111111" else '0';

hann_addr0 <= std_logic_vector(r_cnt3);
ram_addr3  <= std_logic_vector(r_cnt3);

product3 <= signed(sample) * signed(hann0);
ram_data3 <= std_logic_vector(product3(47 downto 24));

p_count_12kHz: process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            r_cnt12 <= (others => '0');
        elsif f_en_cnt12 = '1' then
            r_cnt12 <= r_cnt12 + 1;  -- increment counter
        end if;
    end if;
end process;

f_done_12 <= '1' when r_cnt12(6 downto 0) = "1111111" else '0';

hann_addr1 <= std_logic_vector(r_cnt12);
ram_addr12  <= std_logic_vector(r_cnt12);

product12 <= signed(sample) * signed(hann1);
ram_data12 <= std_logic_vector(product12(47 downto 24));

p_count_48kHz: process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            r_cnt48 <= (others => '0');
        elsif f_en_cnt48 = '1' then
            r_cnt48 <= r_cnt48 + 1;  -- increment counter
        end if;
    end if;
end process;

f_done_48 <= '1' when r_cnt48(6 downto 0) = "1111111" else '0';

hann_addr2 <= std_logic_vector(r_cnt48);
ram_addr48  <= std_logic_vector(r_cnt48);

product48 <= signed(sample) * signed(hann2);
ram_data48 <= std_logic_vector(product48(47 downto 24));

end arch;
