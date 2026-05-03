library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bram_sp is
    generic (
        DATA_WIDTH : integer := 24;
        ADDR_WIDTH : integer := 12
    );
    port (
        clk    : in  STD_LOGIC;

        -- Write port
        we     : in  STD_LOGIC;
        w_addr : in  STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
        din    : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);

        -- Read port
        r_addr : in  STD_LOGIC_VECTOR(ADDR_WIDTH-1 downto 0);
        dout   : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0)
    );
end bram_sp;

architecture Behavioral of bram_sp is

    type ram_type is array (0 to (2**ADDR_WIDTH)-1)
        of STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);

    signal ram    : ram_type;
    signal r_dout : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);

begin

    process(clk)
    begin
        if rising_edge(clk) then

            -- Write operation
            if we = '1' then
                ram(to_integer(unsigned(w_addr))) <= din;
            end if;

            -- Read operation (independent address)
            r_dout <= ram(to_integer(unsigned(r_addr)));

        end if;
    end process;

    dout <= r_dout;

end Behavioral;