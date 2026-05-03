----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05/02/2026 07:36:16 PM
-- Design Name: 
-- Module Name: DataProcessorController - arch
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

entity DataProcessorController is
Port (
    clk     :   in std_logic;
    rst     :   in std_logic;
    
    -- External 
    RAM_WE3     :   out std_logic;
    RAM_WE12    :   out std_logic;
    RAM_WE48    :   out std_logic;
    G_EN3       :   out std_logic;
    G_EN12      :   out std_logic;
    G_EN48      :   out std_logic;
    G_DONE3     :   in std_logic;
    G_DONE12    :   in std_logic;
    G_DONE48    :   in std_logic;
    
    -- Datapath interface
    f_en_cnt3   :   out std_logic;
    f_en_data3  :   out std_logic;
    clk3kHz     :   in std_logic;
    f_done_3    :   in std_logic;
    
    f_en_cnt12  :   out std_logic;
    f_en_data12 :   out std_logic;
    clk12kHz    :   in std_logic;
    f_done_12   :   in std_logic;
    
    f_en_cnt48  :   out std_logic;
    f_en_data48 : out std_logic;
    clk48kHz    :   in std_logic;
    f_done_48   :   in std_logic 

);
end DataProcessorController;

architecture arch of DataProcessorController is
type t_SM_DP is (s_IDLE, s_LDDATA, s_WERAM, s_DONECHK, s_DOG);
signal r_SM_Main3, r_SM_Main12, r_SM_Main48  : t_SM_DP := s_IDLE; 
  
begin

p_sm_DP3: process(clk, rst)
begin
    if rst = '1' then
        r_SM_Main3 <= s_IDLE;
    elsif rising_edge(clk) then
        f_en_cnt3 <= '0';
        f_en_data3 <= '0';
        RAM_WE3 <= '0';
        G_EN3 <= '0';
        
        case r_SM_Main3 is
        
        when s_IDLE =>
            if clk3kHz = '1' then
                r_SM_Main3 <= s_LDDATA;
            end if;
        
        when s_LDDATA =>
            f_en_data3 <= '1';
            r_SM_Main3 <= s_WERAM;
            
        when s_WERAM =>
            RAM_WE3 <= '1';
            r_SM_Main3 <= s_IDLE;
            if f_done_3 = '1' then
                r_SM_Main3 <= s_DONECHK;  
            end if;
            
        when s_DONECHK =>
            if G_DONE3 = '1' then
                r_SM_Main3 <= s_DOG; 
            end if;
        
        when s_DOG =>
            G_EN3 <= '1';
            if G_DONE3 = '0' then
                r_SM_Main3 <= s_IDLE;    
            end if;
        
        when others =>
            r_SM_Main3 <= s_IDLE; 
            
        end case;  
            
    end if;
        
end process;

p_sm_DP12: process(clk, rst)
begin
    if rst = '1' then
        r_SM_Main12 <= s_IDLE;
    elsif rising_edge(clk) then
        f_en_cnt12 <= '0';
        f_en_data12 <= '0';
        RAM_WE12 <= '0';
        G_EN12 <= '0';
        
        case r_SM_Main12 is
        
        when s_IDLE =>
            if clk12kHz = '1' then
                r_SM_Main12 <= s_LDDATA;
            end if;
        
        when s_LDDATA =>
            f_en_data12 <= '1';
            r_SM_Main12 <= s_WERAM;
            
        when s_WERAM =>
            RAM_WE12 <= '1';
            r_SM_Main12 <= s_IDLE;
            if f_done_12 = '1' then
                r_SM_Main12 <= s_DONECHK;  
            end if;
            
        when s_DONECHK =>
            if G_DONE12 = '1' then
                r_SM_Main12 <= s_DOG; 
            end if;
        
        when s_DOG =>
            G_EN12 <= '1';
            if G_DONE12 = '0' then
                r_SM_Main12 <= s_IDLE;    
            end if;
        
        when others =>
            r_SM_Main12 <= s_IDLE; 
            
        end case;  
            
    end if;
        
end process;

p_sm_DP48: process(clk, rst)
begin
    if rst = '1' then
        r_SM_Main48 <= s_IDLE;
    elsif rising_edge(clk) then
        f_en_cnt48 <= '0';
        f_en_data48 <= '0';
        RAM_WE48 <= '0';
        G_EN48 <= '0';
        
        case r_SM_Main48 is
        
        when s_IDLE =>
            if clk48kHz = '1' then
                r_SM_Main48 <= s_LDDATA;
            end if;
        
        when s_LDDATA =>
            f_en_data48 <= '1';
            r_SM_Main48 <= s_WERAM;
            
        when s_WERAM =>
            RAM_WE48 <= '1';
            r_SM_Main48 <= s_IDLE;
            if f_done_48 = '1' then
                r_SM_Main48 <= s_DONECHK;  
            end if;
            
        when s_DONECHK =>
            if G_DONE48 = '1' then
                r_SM_Main48 <= s_DOG; 
            end if;
        
        when s_DOG =>
            G_EN48 <= '1';
            if G_DONE48 = '0' then
                r_SM_Main48 <= s_IDLE;    
            end if;
        
        when others =>
            r_SM_Main48 <= s_IDLE; 
            
        end case;  
            
    end if;
        
end process;

end arch;
