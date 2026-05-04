----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05/04/2026 12:57:24 AM
-- Design Name: 
-- Module Name: DataProcessor_tb - Behavioral
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

entity DataProcessor_tb is
--  Port ( );
end DataProcessor_tb;

architecture Behavioral of DataProcessor_tb is

constant period : time := 20 ns;
signal clk : std_logic := '0';
signal rst : std_logic := '0';

signal done0, done1, done2 : std_logic;
signal en0, en1, en2 : std_logic;
signal ram_addr0, ram_addr1, ram_addr2 : std_logic_vector(11 downto 0);
signal ram_data0, ram_data1, ram_data2 : std_logic_vector(23 downto 0);
signal sample : std_logic_vector(23 downto 0);

-- Component declaration
component design_1_wrapper is
  port (
    clk        : in  STD_LOGIC;
    done0      : in  STD_LOGIC;
    done1      : in  STD_LOGIC;
    done2      : in  STD_LOGIC;
    en0        : out STD_LOGIC;
    en1        : out STD_LOGIC;
    en2        : out STD_LOGIC;
    ram_addr0  : in  STD_LOGIC_VECTOR (11 downto 0);
    ram_addr1  : in  STD_LOGIC_VECTOR (11 downto 0);
    ram_addr2  : in  STD_LOGIC_VECTOR (11 downto 0);
    ram_data0  : out STD_LOGIC_VECTOR (23 downto 0);
    ram_data1  : out STD_LOGIC_VECTOR (23 downto 0);
    ram_data2  : out STD_LOGIC_VECTOR (23 downto 0);
    rst        : in  STD_LOGIC;
    sample     : in  STD_LOGIC_VECTOR (23 downto 0)
  );
end component;

begin

-- Clock generation
clk <= not clk after period/2;

-- DUT Instantiation
UUT: design_1_wrapper
  port map (
    clk        => clk,
    rst        => rst,
    done0      => done0,
    done1      => done1,
    done2      => done2,
    en0        => en0,
    en1        => en1,
    en2        => en2,
    ram_addr0  => ram_addr0,
    ram_addr1  => ram_addr1,
    ram_addr2  => ram_addr2,
    ram_data0  => ram_data0,
    ram_data1  => ram_data1,
    ram_data2  => ram_data2,
    sample     => sample
  );
  
  
controller: process
begin
    done0 <= '1';
    if en0 = '1' then
        done0 <= '0';
        wait for 20 ns;
    end if;

    done1 <= '1';
    if en1 = '1' then
        done1 <= '0';
        wait for 20 ns;
    end if;

    done2 <= '1';
    if en2 = '1' then
        done2 <= '0';
        wait for 20 ns;
    end if;

    wait for 20 ns;  -- prevents zero-time looping
end process;
  
test_process: process
begin
    rst <= '1';
    sample <= "000000000000000000000101";
    
    wait for period*2;
    rst <= '0';
    
    wait for 20ms;
    
    for i in 0 to 4095 loop
        ram_addr0 <= std_logic_vector(to_unsigned(i, 12));
        ram_addr1 <= std_logic_vector(to_unsigned(i, 12));
        ram_addr2 <= std_logic_vector(to_unsigned(i, 12));
    
        wait for 20 ns;  -- wait for data to propagate (1 clock cycle typically)
    
        -- Optional: print values to console
        report "ADDR=" & integer'image(i) &
               " DATA0=" & integer'image(to_integer(unsigned(ram_data0))) &
               " DATA1=" & integer'image(to_integer(unsigned(ram_data1))) &
               " DATA2=" & integer'image(to_integer(unsigned(ram_data2)));
    end loop;
    
    wait;
--        streami_tdata <= x"AAAAAAAA";
--        wait for period;
--        streami_tdata <= x"55555555";
     
    
--    wait until streamo_tready = '0';
    
   
end process;


end Behavioral;
