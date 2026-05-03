----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05/02/2026 10:25:25 PM
-- Design Name: 
-- Module Name: DataProcessorTop - Structural
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity DataProcessorTop is
Port (
    clk     :   std_logic;
    rst     :   std_logic;
    
    sample  :   std_logic_vector(23 downto 0);
    
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
    
    RAM_WE3     :   out std_logic;
    RAM_WE12    :   out std_logic;
    RAM_WE48    :   out std_logic;
    G_EN3       :   out std_logic;
    G_EN12      :   out std_logic;
    G_EN48      :   out std_logic;
    G_DONE3     :   in std_logic;
    G_DONE12    :   in std_logic;
    G_DONE48    :   in std_logic
    
 );
end DataProcessorTop;

architecture Structural of DataProcessorTop is


-- Internal signals
signal f_en_cnt3    : std_logic;
signal f_en_data3   : std_logic;
signal clk3kHz      : std_logic;
signal f_done_3     : std_logic;

signal f_en_cnt12   : std_logic;
signal f_en_data12  : std_logic;
signal clk12kHz     : std_logic;
signal f_done_12    : std_logic;

signal f_en_cnt48   : std_logic;
signal f_en_data48  : std_logic;
signal clk48kHz     : std_logic;
signal f_done_48    : std_logic;

begin

-- ============================================================
-- Controller
-- ============================================================
Controller: entity work.DataProcessorController(arch)
port map(
    clk => clk,
    rst => rst,

    -- External
    RAM_WE3  => RAM_WE3,
    RAM_WE12 => RAM_WE12,
    RAM_WE48 => RAM_WE48,
    G_EN3    => G_EN3,
    G_EN12   => G_EN12,
    G_EN48   => G_EN48,
    G_DONE3  => G_DONE3,
    G_DONE12 => G_DONE12,
    G_DONE48 => G_DONE48,

    -- Datapath interface
    f_en_cnt3   => f_en_cnt3,
    f_en_data3  => f_en_data3,
    clk3kHz     => clk3kHz,
    f_done_3    => f_done_3,

    f_en_cnt12  => f_en_cnt12,
    f_en_data12 => f_en_data12,
    clk12kHz    => clk12kHz,
    f_done_12   => f_done_12,

    f_en_cnt48  => f_en_cnt48,
    f_en_data48 => f_en_data48,
    clk48kHz    => clk48kHz,
    f_done_48   => f_done_48
);


-- ============================================================
-- Datapath
-- ============================================================
Datapath: entity work.DataProcessorDatapath(arch)
port map(
    -- System
    clk => clk,
    rst => rst,

    -- Input data
    sample => sample,

    hann0 => hann0,
    hann1 => hann1,
    hann2 => hann2,

    hann_addr0 => hann_addr0,
    hann_addr1 => hann_addr1,
    hann_addr2 => hann_addr2,

    ram_addr3  => ram_addr3,
    ram_addr12 => ram_addr12,
    ram_addr48 => ram_addr48,

    ram_data3  => ram_data3,
    ram_data12 => ram_data12,
    ram_data48 => ram_data48,

    -- Controller interface
    f_en_cnt3   => f_en_cnt3,
    f_en_data3  => f_en_data3,
    clk3kHz     => clk3kHz,
    f_done_3    => f_done_3,

    f_en_cnt12  => f_en_cnt12,
    f_en_data12 => f_en_data12,
    clk12kHz    => clk12kHz,
    f_done_12   => f_done_12,

    f_en_cnt48  => f_en_cnt48,
    f_en_data48 => f_en_data48,
    clk48kHz    => clk48kHz,
    f_done_48   => f_done_48
);

end Structural;
