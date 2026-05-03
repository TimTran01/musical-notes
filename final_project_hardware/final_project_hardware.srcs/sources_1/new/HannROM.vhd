----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/27/2026 09:55:00 PM
-- Design Name: 
-- Module Name: HannROM - Behavioral
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
use IEEE.NUMERIC_STD.ALL;
--use ieee.std_logic_unsigned.all;
-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity HannROM is
    Port ( 
    clk     :   in std_logic;
    addr0   :   in std_logic_vector(11 downto 0);
    addr1   :   in std_logic_vector(11 downto 0);
    addr2   :   in std_logic_vector(11 downto 0);
    
    data0    :   out std_logic_vector(23 downto 0);
    data1    :   out std_logic_vector(23 downto 0);
    data2    :   out std_logic_vector(23 downto 0)
    
    );
end HannROM;

architecture RTL of HannROM is

    -- ROM now only stores 2048 samples (Half-depth)
    type rom_type is array (0 to 2047) of std_logic_vector(23 downto 0);
    constant ROM : rom_type := (  
    x"000000", x"00000A", x"000027", x"000059", x"00009E", x"0000F7", x"000163", x"0001E4",
    x"000278", x"000320", x"0003DB", x"0004AB", x"00058E", x"000685", x"00078F", x"0008AE",
    x"0009E0", x"000B26", x"000C7F", x"000DEC", x"000F6D", x"001102", x"0012AB", x"001467",
    x"001637", x"00181B", x"001A12", x"001C1D", x"001E3C", x"00206F", x"0022B5", x"002510",
    x"00277D", x"0029FF", x"002C94", x"002F3D", x"0031FA", x"0034CA", x"0037AF", x"003AA7",
    x"003DB2", x"0040D1", x"004404", x"00474B", x"004AA6", x"004E14", x"005196", x"00552B",
    x"0058D4", x"005C91", x"006062", x"006446", x"00683E", x"006C4A", x"007069", x"00749C",
    x"0078E3", x"007D3E", x"0081AC", x"00862D", x"008AC3", x"008F6C", x"009429", x"0098F9",
    x"009DDD", x"00A2D5", x"00A7E0", x"00ACFF", x"00B232", x"00B778", x"00BCD2", x"00C240",
    x"00C7C1", x"00CD56", x"00D2FE", x"00D8BA", x"00DE8A", x"00E46D", x"00EA64", x"00F06F",
    x"00F68D", x"00FCBF", x"010304", x"01095D", x"010FCA", x"01164A", x"011CDD", x"012385",
    x"012A3F", x"01310E", x"0137F0", x"013EE5", x"0145EE", x"014D0B", x"01543B", x"015B7F",
    x"0162D6", x"016A41", x"0171BF", x"017951", x"0180F7", x"0188B0", x"01907C", x"01985C",
    x"01A04F", x"01A856", x"01B071", x"01B89F", x"01C0E0", x"01C935", x"01D19D", x"01DA19",
    x"01E2A8", x"01EB4B", x"01F401", x"01FCCB", x"0205A8", x"020E98", x"02179C", x"0220B4",
    x"0229DE", x"02331D", x"023C6E", x"0245D3", x"024F4C", x"0258D8", x"026277", x"026C29",
    x"0275EF", x"027FC9", x"0289B5", x"0293B5", x"029DC9", x"02A7EF", x"02B229", x"02BC77",
    x"02C6D8", x"02D14C", x"02DBD3", x"02E66E", x"02F11C", x"02FBDD", x"0306B1", x"031199",
    x"031C94", x"0327A3", x"0332C4", x"033DF9", x"034942", x"03549D", x"03600C", x"036B8D",
    x"037722", x"0382CB", x"038E86", x"039A55", x"03A637", x"03B22C", x"03BE34", x"03CA50",
    x"03D67E", x"03E2C0", x"03EF15", x"03FB7D", x"0407F8", x"041486", x"042128", x"042DDC",
    x"043AA4", x"04477F", x"04546D", x"04616D", x"046E81", x"047BA8", x"0488E3", x"049630",
    x"04A390", x"04B103", x"04BE89", x"04CC23", x"04D9CF", x"04E78E", x"04F560", x"050346",
    x"05113E", x"051F49", x"052D67", x"053B98", x"0549DC", x"055833", x"05669D", x"05751A",
    x"0583AA", x"05924C", x"05A102", x"05AFCA", x"05BEA6", x"05CD94", x"05DC95", x"05EBA8",
    x"05FACF", x"060A09", x"061955", x"0628B4", x"063826", x"0647AB", x"065742", x"0666EC",
    x"0676A9", x"068679", x"06965C", x"06A651", x"06B659", x"06C673", x"06D6A1", x"06E6E1",
    x"06F734", x"070799", x"071811", x"07289C", x"073939", x"0749E9", x"075AAC", x"076B81",
    x"077C69", x"078D64", x"079E71", x"07AF90", x"07C0C2", x"07D207", x"07E35E", x"07F4C8",
    x"080644", x"0817D3", x"082975", x"083B28", x"084CEF", x"085EC8", x"0870B3", x"0882B0",
    x"0894C1", x"08A6E3", x"08B918", x"08CB5F", x"08DDB9", x"08F025", x"0902A4", x"091535",
    x"0927D8", x"093A8D", x"094D55", x"09602F", x"09731C", x"09861B", x"09992C", x"09AC4F",
    x"09BF85", x"09D2CC", x"09E626", x"09F993", x"0A0D11", x"0A20A2", x"0A3445", x"0A47FA",
    x"0A5BC1", x"0A6F9A", x"0A8386", x"0A9784", x"0AAB93", x"0ABFB5", x"0AD3E9", x"0AE82F",
    x"0AFC87", x"0B10F1", x"0B256D", x"0B39FC", x"0B4E9C", x"0B634E", x"0B7812", x"0B8CE8",
    x"0BA1D1", x"0BB6CB", x"0BCBD7", x"0BE0F5", x"0BF625", x"0C0B66", x"0C20BA", x"0C3620",
    x"0C4B97", x"0C6120", x"0C76BC", x"0C8C68", x"0CA227", x"0CB7F8", x"0CCDDA", x"0CE3CE",
    x"0CF9D4", x"0D0FEC", x"0D2615", x"0D3C50", x"0D529D", x"0D68FC", x"0D7F6C", x"0D95ED",
    x"0DAC81", x"0DC326", x"0DD9DD", x"0DF0A5", x"0E077F", x"0E1E6B", x"0E3568", x"0E4C76",
    x"0E6397", x"0E7AC8", x"0E920C", x"0EA960", x"0EC0C7", x"0ED83E", x"0EEFC8", x"0F0762",
    x"0F1F0E", x"0F36CC", x"0F4E9B", x"0F667B", x"0F7E6C", x"0F966F", x"0FAE84", x"0FC6A9",
    x"0FDEE0", x"0FF729", x"100F82", x"1027ED", x"104069", x"1058F6", x"107195", x"108A45",
    x"10A306", x"10BBD8", x"10D4BB", x"10EDB0", x"1106B5", x"111FCC", x"1138F4", x"11522D",
    x"116B77", x"1184D2", x"119E3E", x"11B7BB", x"11D149", x"11EAE8", x"120498", x"121E5A",
    x"12382C", x"12520F", x"126C02", x"128607", x"12A01D", x"12BA44", x"12D47B", x"12EEC3",
    x"13091C", x"132386", x"133E01", x"13588D", x"137329", x"138DD6", x"13A894", x"13C362",
    x"13DE41", x"13F931", x"141432", x"142F43", x"144A65", x"146597", x"1480DA", x"149C2E",
    x"14B792", x"14D307", x"14EE8C", x"150A22", x"1525C8", x"15417F", x"155D46", x"15791E",
    x"159506", x"15B0FE", x"15CD07", x"15E921", x"16054A", x"162184", x"163DCF", x"165A29",
    x"167694", x"169310", x"16AF9B", x"16CC37", x"16E8E3", x"17059F", x"17226C", x"173F48",
    x"175C35", x"177932", x"17963F", x"17B35C", x"17D08A", x"17EDC7", x"180B14", x"182872",
    x"1845DF", x"18635D", x"1880EA", x"189E88", x"18BC35", x"18D9F2", x"18F7BF", x"19159D",
    x"19338A", x"195186", x"196F93", x"198DB0", x"19ABDC", x"19CA18", x"19E864", x"1A06C0",
    x"1A252B", x"1A43A6", x"1A6231", x"1A80CB", x"1A9F75", x"1ABE2F", x"1ADCF8", x"1AFBD1",
    x"1B1ABA", x"1B39B2", x"1B58BA", x"1B77D1", x"1B96F8", x"1BB62E", x"1BD574", x"1BF4C9",
    x"1C142D", x"1C33A1", x"1C5325", x"1C72B8", x"1C925A", x"1CB20B", x"1CD1CC", x"1CF19C",
    x"1D117B", x"1D316A", x"1D5168", x"1D7175", x"1D9191", x"1DB1BD", x"1DD1F8", x"1DF241",
    x"1E129A", x"1E3302", x"1E5379", x"1E7400", x"1E9495", x"1EB539", x"1ED5ED", x"1EF6AF",
    x"1F1780", x"1F3860", x"1F5950", x"1F7A4E", x"1F9B5B", x"1FBC76", x"1FDDA1", x"1FFEDB",
    x"202023", x"20417A", x"2062E0", x"208455", x"20A5D8", x"20C76A", x"20E90B", x"210ABA",
    x"212C78", x"214E45", x"217020", x"21920A", x"21B403", x"21D60A", x"21F820", x"221A44",
    x"223C76", x"225EB7", x"228107", x"22A365", x"22C5D1", x"22E84C", x"230AD5", x"232D6C",
    x"235012", x"2372C6", x"239588", x"23B859", x"23DB38", x"23FE25", x"242120", x"244429",
    x"246741", x"248A66", x"24AD9A", x"24D0DC", x"24F42C", x"25178A", x"253AF6", x"255E70",
    x"2581F8", x"25A58E", x"25C932", x"25ECE4", x"2610A3", x"263471", x"26584D", x"267C36",
    x"26A02D", x"26C432", x"26E844", x"270C65", x"273093", x"2754CF", x"277918", x"279D6F",
    x"27C1D4", x"27E647", x"280AC7", x"282F54", x"2853EF", x"287898", x"289D4E", x"28C212",
    x"28E6E3", x"290BC2", x"2930AD", x"2955A7", x"297AAE", x"299FC2", x"29C4E3", x"29EA12",
    x"2A0F4E", x"2A3497", x"2A59ED", x"2A7F51", x"2AA4C2", x"2ACA40", x"2AEFCB", x"2B1564",
    x"2B3B09", x"2B60BC", x"2B867B", x"2BAC48", x"2BD221", x"2BF808", x"2C1DFC", x"2C43FC",
    x"2C6A09", x"2C9024", x"2CB64B", x"2CDC7F", x"2D02C0", x"2D290E", x"2D4F68", x"2D75CF",
    x"2D9C43", x"2DC2C4", x"2DE951", x"2E0FEB", x"2E3692", x"2E5D45", x"2E8405", x"2EAAD2",
    x"2ED1AB", x"2EF890", x"2F1F82", x"2F4681", x"2F6D8C", x"2F94A3", x"2FBBC7", x"2FE2F7",
    x"300A33", x"30317C", x"3058D1", x"308033", x"30A7A1", x"30CF1B", x"30F6A1", x"311E33",
    x"3145D2", x"316D7D", x"319533", x"31BCF6", x"31E4C5", x"320CA0", x"323487", x"325C7B",
    x"32847A", x"32AC85", x"32D49C", x"32FCBE", x"3324ED", x"334D28", x"33756E", x"339DC1",
    x"33C61F", x"33EE88", x"3416FE", x"343F7F", x"34680C", x"3490A5", x"34B949", x"34E1F9",
    x"350AB4", x"35337B", x"355C4E", x"35852C", x"35AE15", x"35D70A", x"36000B", x"362917",
    x"36522E", x"367B50", x"36A47E", x"36CDB8", x"36F6FC", x"37204C", x"3749A7", x"37730E",
    x"379C7F", x"37C5FC", x"37EF84", x"381917", x"3842B5", x"386C5E", x"389612", x"38BFD1",
    x"38E99B", x"391370", x"393D50", x"39673B", x"399131", x"39BB32", x"39E53E", x"3A0F54",
    x"3A3975", x"3A63A1", x"3A8DD8", x"3AB819", x"3AE265", x"3B0CBC", x"3B371E", x"3B618A",
    x"3B8C00", x"3BB681", x"3BE10D", x"3C0BA3", x"3C3644", x"3C60EF", x"3C8BA5", x"3CB665",
    x"3CE12F", x"3D0C04", x"3D36E3", x"3D61CC", x"3D8CC0", x"3DB7BE", x"3DE2C6", x"3E0DD8",
    x"3E38F5", x"3E641B", x"3E8F4C", x"3EBA87", x"3EE5CC", x"3F111B", x"3F3C74", x"3F67D7",
    x"3F9344", x"3FBEBB", x"3FEA3C", x"4015C6", x"40415B", x"406CF9", x"4098A2", x"40C453",
    x"40F00F", x"411BD5", x"4147A4", x"41737D", x"419F5F", x"41CB4B", x"41F741", x"422340",
    x"424F49", x"427B5C", x"42A777", x"42D39D", x"42FFCC", x"432C04", x"435845", x"438490",
    x"43B0E4", x"43DD42", x"4409A9", x"443619", x"446292", x"448F15", x"44BBA0", x"44E835",
    x"4514D3", x"45417A", x"456E2A", x"459AE3", x"45C7A5", x"45F471", x"462145", x"464E22",
    x"467B08", x"46A7F6", x"46D4EE", x"4701EE", x"472EF8", x"475C0A", x"478924", x"47B648",
    x"47E374", x"4810A9", x"483DE6", x"486B2C", x"48987B", x"48C5D2", x"48F332", x"49209A",
    x"494E0A", x"497B84", x"49A905", x"49D68F", x"4A0421", x"4A31BC", x"4A5F5F", x"4A8D0A",
    x"4ABABD", x"4AE879", x"4B163C", x"4B4408", x"4B71DC", x"4B9FB9", x"4BCD9D", x"4BFB89",
    x"4C297E", x"4C577A", x"4C857E", x"4CB38B", x"4CE19F", x"4D0FBB", x"4D3DDF", x"4D6C0B",
    x"4D9A3E", x"4DC879", x"4DF6BC", x"4E2507", x"4E535A", x"4E81B4", x"4EB016", x"4EDE7F",
    x"4F0CF0", x"4F3B69", x"4F69E9", x"4F9870", x"4FC6FF", x"4FF596", x"502434", x"5052D9",
    x"508186", x"50B03A", x"50DEF5", x"510DB7", x"513C81", x"516B52", x"519A2A", x"51C90A",
    x"51F7F0", x"5226DE", x"5255D2", x"5284CE", x"52B3D1", x"52E2DA", x"5311EB", x"534102",
    x"537021", x"539F46", x"53CE72", x"53FDA5", x"542CDF", x"545C20", x"548B67", x"54BAB5",
    x"54EA0A", x"551965", x"5548C7", x"557830", x"55A79F", x"55D714", x"560691", x"563613",
    x"56659C", x"56952C", x"56C4C2", x"56F45E", x"572400", x"5753A9", x"578358", x"57B30E",
    x"57E2C9", x"58128B", x"584253", x"587221", x"58A1F5", x"58D1D0", x"5901B0", x"593196",
    x"596183", x"599175", x"59C16D", x"59F16B", x"5A216F", x"5A5179", x"5A8189", x"5AB19E",
    x"5AE1B9", x"5B11DA", x"5B4201", x"5B722D", x"5BA25F", x"5BD296", x"5C02D4", x"5C3316",
    x"5C635E", x"5C93AC", x"5CC3FF", x"5CF458", x"5D24B6", x"5D5519", x"5D8582", x"5DB5F0",
    x"5DE663", x"5E16DC", x"5E475A", x"5E77DD", x"5EA865", x"5ED8F2", x"5F0985", x"5F3A1C",
    x"5F6AB9", x"5F9B5A", x"5FCC01", x"5FFCAC", x"602D5D", x"605E12", x"608ECD", x"60BF8C",
    x"60F050", x"612119", x"6151E6", x"6182B8", x"61B38F", x"61E46B", x"62154B", x"624630",
    x"62771A", x"62A808", x"62D8FA", x"6309F2", x"633AED", x"636BED", x"639CF1", x"63CDFA",
    x"63FF07", x"643019", x"64612F", x"649249", x"64C367", x"64F489", x"6525B0", x"6556DB",
    x"658809", x"65B93C", x"65EA73", x"661BAE", x"664CED", x"667E30", x"66AF77", x"66E0C2",
    x"671211", x"674363", x"6774BA", x"67A614", x"67D772", x"6808D4", x"683A39", x"686BA2",
    x"689D0F", x"68CE7F", x"68FFF3", x"69316A", x"6962E5", x"699463", x"69C5E5", x"69F76A",
    x"6A28F3", x"6A5A7F", x"6A8C0E", x"6ABDA1", x"6AEF37", x"6B20D0", x"6B526D", x"6B840C",
    x"6BB5AF", x"6BE755", x"6C18FE", x"6C4AAA", x"6C7C59", x"6CAE0C", x"6CDFC1", x"6D1179",
    x"6D4334", x"6D74F2", x"6DA6B2", x"6DD876", x"6E0A3C", x"6E3C06", x"6E6DD1", x"6E9FA0",
    x"6ED171", x"6F0345", x"6F351C", x"6F66F5", x"6F98D1", x"6FCAAF", x"6FFC90", x"702E73",
    x"706059", x"709241", x"70C42B", x"70F618", x"712807", x"7159F8", x"718BEC", x"71BDE2",
    x"71EFDA", x"7221D4", x"7253D1", x"7285CF", x"72B7D0", x"72E9D2", x"731BD7", x"734DDE",
    x"737FE6", x"73B1F1", x"73E3FD", x"74160C", x"74481C", x"747A2E", x"74AC41", x"74DE57",
    x"75106E", x"754287", x"7574A2", x"75A6BE", x"75D8DC", x"760AFB", x"763D1C", x"766F3E",
    x"76A162", x"76D387", x"7705AE", x"7737D6", x"7769FF", x"779C2A", x"77CE56", x"780084",
    x"7832B2", x"7864E2", x"789713", x"78C945", x"78FB78", x"792DAC", x"795FE2", x"799218",
    x"79C450", x"79F688", x"7A28C1", x"7A5AFB", x"7A8D36", x"7ABF72", x"7AF1AF", x"7B23EC",
    x"7B562A", x"7B8869", x"7BBAA9", x"7BECE9", x"7C1F2A", x"7C516C", x"7C83AE", x"7CB5F0",
    x"7CE833", x"7D1A77", x"7D4CBB", x"7D7EFF", x"7DB144", x"7DE389", x"7E15CF", x"7E4815",
    x"7E7A5B", x"7EACA1", x"7EDEE8", x"7F112E", x"7F4375", x"7F75BC", x"7FA803", x"7FDA4A",
    x"800C91", x"803ED8", x"80711F", x"80A366", x"80D5AD", x"8107F4", x"813A3B", x"816C81",
    x"819EC7", x"81D10D", x"820353", x"823598", x"8267DD", x"829A22", x"82CC66", x"82FEAA",
    x"8330ED", x"836330", x"839572", x"83C7B4", x"83F9F5", x"842C36", x"845E76", x"8490B5",
    x"84C2F4", x"84F532", x"85276F", x"8559AB", x"858BE6", x"85BE21", x"85F05B", x"862293",
    x"8654CB", x"868702", x"86B938", x"86EB6D", x"871DA1", x"874FD3", x"878205", x"87B435",
    x"87E664", x"881892", x"884ABF", x"887CEA", x"88AF14", x"88E13D", x"891365", x"89458B",
    x"8977AF", x"89A9D2", x"89DBF4", x"8A0E14", x"8A4033", x"8A7250", x"8AA46B", x"8AD685",
    x"8B089D", x"8B3AB3", x"8B6CC8", x"8B9EDA", x"8BD0EB", x"8C02FB", x"8C3508", x"8C6714",
    x"8C991D", x"8CCB25", x"8CFD2A", x"8D2F2E", x"8D6130", x"8D932F", x"8DC52D", x"8DF728",
    x"8E2921", x"8E5B18", x"8E8D0D", x"8EBF00", x"8EF0F0", x"8F22DE", x"8F54C9", x"8F86B3",
    x"8FB89A", x"8FEA7E", x"901C60", x"904E40", x"90801C", x"90B1F7", x"90E3CF", x"9115A4",
    x"914777", x"917947", x"91AB14", x"91DCDE", x"920EA6", x"92406B", x"92722D", x"92A3ED",
    x"92D5A9", x"930763", x"933919", x"936ACD", x"939C7E", x"93CE2B", x"93FFD6", x"94317D",
    x"946322", x"9494C3", x"94C661", x"94F7FC", x"952993", x"955B28", x"958CB9", x"95BE46",
    x"95EFD1", x"962158", x"9652DB", x"96845B", x"96B5D8", x"96E751", x"9718C7", x"974A39",
    x"977BA7", x"97AD12", x"97DE79", x"980FDD", x"98413D", x"987299", x"98A3F1", x"98D545",
    x"990696", x"9937E3", x"99692C", x"999A71", x"99CBB2", x"99FCEF", x"9A2E28", x"9A5F5D",
    x"9A908D", x"9AC1BA", x"9AF2E3", x"9B2408", x"9B5528", x"9B8644", x"9BB75C", x"9BE86F",
    x"9C197F", x"9C4A8A", x"9C7B90", x"9CAC92", x"9CDD90", x"9D0E8A", x"9D3F7E", x"9D706F",
    x"9DA15B", x"9DD242", x"9E0324", x"9E3402", x"9E64DC", x"9E95B0", x"9EC680", x"9EF74B",
    x"9F2812", x"9F58D3", x"9F8990", x"9FBA48", x"9FEAFB", x"A01BA9", x"A04C52", x"A07CF6",
    x"A0AD95", x"A0DE2F", x"A10EC4", x"A13F54", x"A16FDF", x"A1A065", x"A1D0E5", x"A20160",
    x"A231D6", x"A26247", x"A292B2", x"A2C318", x"A2F379", x"A323D4", x"A3542A", x"A3847A",
    x"A3B4C5", x"A3E50B", x"A4154B", x"A44585", x"A475BA", x"A4A5E9", x"A4D612", x"A50636",
    x"A53654", x"A5666C", x"A5967F", x"A5C68C", x"A5F693", x"A62694", x"A6568F", x"A68684",
    x"A6B673", x"A6E65D", x"A71640", x"A7461D", x"A775F4", x"A7A5C6", x"A7D591", x"A80556",
    x"A83514", x"A864CD", x"A8947F", x"A8C42B", x"A8F3D1", x"A92370", x"A95309", x"A9829C",
    x"A9B228", x"A9E1AE", x"AA112D", x"AA40A6", x"AA7019", x"AA9F84", x"AACEEA", x"AAFE48",
    x"AB2DA0", x"AB5CF2", x"AB8C3C", x"ABBB80", x"ABEABD", x"AC19F4", x"AC4924", x"AC784C",
    x"ACA76E", x"ACD689", x"AD059D", x"AD34AB", x"AD63B1", x"AD92B0", x"ADC1A8", x"ADF099",
    x"AE1F83", x"AE4E66", x"AE7D42", x"AEAC16", x"AEDAE4", x"AF09AA", x"AF3869", x"AF6720",
    x"AF95D1", x"AFC47A", x"AFF31B", x"B021B5", x"B05048", x"B07ED3", x"B0AD57", x"B0DBD4",
    x"B10A48", x"B138B5", x"B1671B", x"B19579", x"B1C3CF", x"B1F21E", x"B22065", x"B24EA4",
    x"B27CDC", x"B2AB0B", x"B2D933", x"B30753", x"B3356B", x"B3637C", x"B39184", x"B3BF84",
    x"B3ED7D", x"B41B6D", x"B44955", x"B47735", x"B4A50E", x"B4D2DE", x"B500A5", x"B52E65",
    x"B55C1D", x"B589CC", x"B5B773", x"B5E512", x"B612A8", x"B64036", x"B66DBC", x"B69B39",
    x"B6C8AE", x"B6F61A", x"B7237E", x"B750DA", x"B77E2D", x"B7AB77", x"B7D8B9", x"B805F2",
    x"B83322", x"B8604A", x"B88D69", x"B8BA7F", x"B8E78D", x"B91492", x"B9418E", x"B96E81",
    x"B99B6B", x"B9C84D", x"B9F525", x"BA21F5", x"BA4EBC", x"BA7B79", x"BAA82E", x"BAD4DA",
    x"BB017C", x"BB2E15", x"BB5AA6", x"BB872D", x"BBB3AB", x"BBE01F", x"BC0C8B", x"BC38ED",
    x"BC6546", x"BC9195", x"BCBDDC", x"BCEA19", x"BD164C", x"BD4276", x"BD6E97", x"BD9AAE",
    x"BDC6BB", x"BDF2BF", x"BE1EBA", x"BE4AAB", x"BE7692", x"BEA270", x"BECE44", x"BEFA0E",
    x"BF25CF", x"BF5186", x"BF7D33", x"BFA8D6", x"BFD470", x"BFFFFF", x"C02B85", x"C05701",
    x"C08273", x"C0ADDB", x"C0D939", x"C1048D", x"C12FD7", x"C15B17", x"C1864C", x"C1B178",
    x"C1DC9A", x"C207B1", x"C232BE", x"C25DC1", x"C288BA", x"C2B3A9", x"C2DE8D", x"C30967",
    x"C33436", x"C35EFC", x"C389B6", x"C3B467", x"C3DF0D", x"C409A8", x"C43439", x"C45EC0",
    x"C4893B", x"C4B3AD", x"C4DE13", x"C50870", x"C532C1", x"C55D08", x"C58744", x"C5B175",
    x"C5DB9C", x"C605B8", x"C62FC9", x"C659CF", x"C683CA", x"C6ADBA", x"C6D7A0", x"C7017B",
    x"C72B4A", x"C7550F", x"C77EC9", x"C7A877", x"C7D21B", x"C7FBB3", x"C82541", x"C84EC3",
    x"C8783A", x"C8A1A6", x"C8CB07", x"C8F45C", x"C91DA6", x"C946E5", x"C97019", x"C99941",
    x"C9C25E", x"C9EB70", x"CA1476", x"CA3D71", x"CA6660", x"CA8F44", x"CAB81C", x"CAE0E9",
    x"CB09AA", x"CB3260", x"CB5B0A", x"CB83A8", x"CBAC3B", x"CBD4C2", x"CBFD3D", x"CC25AD",
    x"CC4E11", x"CC7669", x"CC9EB5", x"CCC6F6", x"CCEF2B", x"CD1753", x"CD3F70", x"CD6781",
    x"CD8F86", x"CDB77F", x"CDDF6D", x"CE074E", x"CE2F23", x"CE56EC", x"CE7EA9", x"CEA659",
    x"CECDFE", x"CEF596", x"CF1D23", x"CF44A3", x"CF6C17", x"CF937E", x"CFBADA", x"CFE229",
    x"D0096B", x"D030A2", x"D057CC", x"D07EE9", x"D0A5FB", x"D0CCFF", x"D0F3F8", x"D11AE3",
    x"D141C3", x"D16895", x"D18F5B", x"D1B615", x"D1DCC2", x"D20362", x"D229F6", x"D2507D",
    x"D276F7", x"D29D65", x"D2C3C6", x"D2EA1A", x"D31061", x"D3369C", x"D35CC9", x"D382EA",
    x"D3A8FE", x"D3CF05", x"D3F4FF", x"D41AEC", x"D440CC", x"D4669F", x"D48C65", x"D4B21E",
    x"D4D7CA", x"D4FD69", x"D522FB", x"D54880", x"D56DF7", x"D59361", x"D5B8BE", x"D5DE0E",
    x"D60351", x"D62886", x"D64DAE", x"D672C9", x"D697D6", x"D6BCD6", x"D6E1C9", x"D706AE",
    x"D72B86", x"D75051", x"D7750E", x"D799BD", x"D7BE5F", x"D7E2F3", x"D8077A", x"D82BF3",
    x"D8505F", x"D874BD", x"D8990D", x"D8BD50", x"D8E185", x"D905AC", x"D929C6", x"D94DD1",
    x"D971CF", x"D995C0", x"D9B9A2", x"D9DD76", x"DA013D", x"DA24F6", x"DA48A1", x"DA6C3E",
    x"DA8FCD", x"DAB34E", x"DAD6C1", x"DAFA26", x"DB1D7D", x"DB40C6", x"DB6401", x"DB872D",
    x"DBAA4C", x"DBCD5C", x"DBF05F", x"DC1353", x"DC3639", x"DC5910", x"DC7BDA", x"DC9E95",
    x"DCC142", x"DCE3E0", x"DD0671", x"DD28F3", x"DD4B66", x"DD6DCB", x"DD9022", x"DDB26A",
    x"DDD4A4", x"DDF6CF", x"DE18EC", x"DE3AFA", x"DE5CFA", x"DE7EEB", x"DEA0CE", x"DEC2A2",
    x"DEE468", x"DF061E", x"DF27C6", x"DF4960", x"DF6AEB", x"DF8C67", x"DFADD4", x"DFCF32",
    x"DFF082", x"E011C3", x"E032F5", x"E05418", x"E0752D", x"E09632", x"E0B729", x"E0D811",
    x"E0F8E9", x"E119B3", x"E13A6E", x"E15B1A", x"E17BB7", x"E19C44", x"E1BCC3", x"E1DD33",
    x"E1FD93", x"E21DE4", x"E23E27", x"E25E5A", x"E27E7E", x"E29E92", x"E2BE98", x"E2DE8E",
    x"E2FE75", x"E31E4D", x"E33E15", x"E35DCF", x"E37D78", x"E39D13", x"E3BC9E", x"E3DC1A",
    x"E3FB86", x"E41AE3", x"E43A30", x"E4596E", x"E4789D", x"E497BC", x"E4B6CB", x"E4D5CB",
    x"E4F4BB", x"E5139C", x"E5326D", x"E5512F", x"E56FE1", x"E58E83", x"E5AD16", x"E5CB99",
    x"E5EA0C", x"E6086F", x"E626C3", x"E64507", x"E6633B", x"E68160", x"E69F74", x"E6BD79",
    x"E6DB6E", x"E6F953", x"E71728", x"E734ED", x"E752A3", x"E77048", x"E78DDE", x"E7AB63",
    x"E7C8D8", x"E7E63E", x"E80393", x"E820D9", x"E83E0E", x"E85B33", x"E87848", x"E8954D",
    x"E8B242", x"E8CF27", x"E8EBFB", x"E908C0", x"E92574", x"E94218", x"E95EAC", x"E97B2F",
    x"E997A2", x"E9B405", x"E9D058", x"E9EC9A", x"EA08CC", x"EA24ED", x"EA40FE", x"EA5CFF",
    x"EA78EF", x"EA94CF", x"EAB09F", x"EACC5E", x"EAE80C", x"EB03AA", x"EB1F38", x"EB3AB5",
    x"EB5621", x"EB717D", x"EB8CC9", x"EBA803", x"EBC32D", x"EBDE47", x"EBF950", x"EC1448",
    x"EC2F2F", x"EC4A06", x"EC64CC", x"EC7F82", x"EC9A26", x"ECB4BA", x"ECCF3D", x"ECE9B0",
    x"ED0411", x"ED1E62", x"ED38A2", x"ED52D1", x"ED6CEF", x"ED86FC", x"EDA0F9", x"EDBAE4",
    x"EDD4BF", x"EDEE88", x"EE0841", x"EE21E8", x"EE3B7F", x"EE5505", x"EE6E79", x"EE87DD",
    x"EEA12F", x"EEBA71", x"EED3A1", x"EEECC1", x"EF05CF", x"EF1ECC", x"EF37B8", x"EF5092",
    x"EF695C", x"EF8214", x"EF9ABB", x"EFB351", x"EFCBD6", x"EFE44A", x"EFFCAC", x"F014FD",
    x"F02D3C", x"F0456B", x"F05D88", x"F07593", x"F08D8E", x"F0A576", x"F0BD4E", x"F0D514",
    x"F0ECC9", x"F1046C", x"F11BFE", x"F1337F", x"F14AEE", x"F1624B", x"F17997", x"F190D2",
    x"F1A7FB", x"F1BF12", x"F1D618", x"F1ED0C", x"F203EF", x"F21AC0", x"F23180", x"F2482E",
    x"F25ECA", x"F27555", x"F28BCE", x"F2A235", x"F2B88B", x"F2CECF", x"F2E501", x"F2FB21",
    x"F31130", x"F3272D", x"F33D18", x"F352F2", x"F368B9", x"F37E6F", x"F39413", x"F3A9A5",
    x"F3BF26", x"F3D494", x"F3E9F1", x"F3FF3C", x"F41475", x"F4299C", x"F43EB1", x"F453B4",
    x"F468A5", x"F47D84", x"F49251", x"F4A70C", x"F4BBB6", x"F4D04D", x"F4E4D2", x"F4F945",
    x"F50DA6", x"F521F5", x"F53632", x"F54A5D", x"F55E76", x"F5727D", x"F58671", x"F59A54",
    x"F5AE24", x"F5C1E2", x"F5D58E", x"F5E928", x"F5FCAF", x"F61025", x"F62388", x"F636D9",
    x"F64A17", x"F65D44", x"F6705E", x"F68366", x"F6965C", x"F6A93F", x"F6BC10", x"F6CECF",
    x"F6E17B", x"F6F415", x"F7069D", x"F71912", x"F72B75", x"F73DC6", x"F75004", x"F7622F",
    x"F77449", x"F78650", x"F79844", x"F7AA26", x"F7BBF6", x"F7CDB3", x"F7DF5D", x"F7F0F5",
    x"F8027B", x"F813EE", x"F8254F", x"F8369D", x"F847D8", x"F85901", x"F86A17", x"F87B1B",
    x"F88C0C", x"F89CEB", x"F8ADB7", x"F8BE70", x"F8CF17", x"F8DFAB", x"F8F02C", x"F9009B",
    x"F910F7", x"F92140", x"F93177", x"F9419B", x"F951AD", x"F961AB", x"F97197", x"F98170",
    x"F99137", x"F9A0EA", x"F9B08B", x"F9C019", x"F9CF94", x"F9DEFD", x"F9EE53", x"F9FD95",
    x"FA0CC6", x"FA1BE3", x"FA2AED", x"FA39E5", x"FA48C9", x"FA579B", x"FA665A", x"FA7506",
    x"FA839F", x"FA9226", x"FAA099", x"FAAEFA", x"FABD47", x"FACB82", x"FAD9A9", x"FAE7BE",
    x"FAF5C0", x"FB03AE", x"FB118A", x"FB1F53", x"FB2D09", x"FB3AAB", x"FB483B", x"FB55B8",
    x"FB6322", x"FB7078", x"FB7DBC", x"FB8AEC", x"FB980A", x"FBA514", x"FBB20C", x"FBBEF0",
    x"FBCBC1", x"FBD87F", x"FBE52A", x"FBF1C2", x"FBFE47", x"FC0AB8", x"FC1717", x"FC2362",
    x"FC2F9A", x"FC3BBF", x"FC47D1", x"FC53D0", x"FC5FBB", x"FC6B94", x"FC7759", x"FC830B",
    x"FC8EA9", x"FC9A35", x"FCA5AD", x"FCB112", x"FCBC64", x"FCC7A2", x"FCD2CE", x"FCDDE6",
    x"FCE8EB", x"FCF3DC", x"FCFEBA", x"FD0985", x"FD143D", x"FD1EE1", x"FD2972", x"FD33F0",
    x"FD3E5A", x"FD48B1", x"FD52F5", x"FD5D25", x"FD6742", x"FD714C", x"FD7B43", x"FD8526",
    x"FD8EF5", x"FD98B1", x"FDA25A", x"FDABF0", x"FDB572", x"FDBEE1", x"FDC83C", x"FDD184",
    x"FDDAB8", x"FDE3D9", x"FDECE7", x"FDF5E1", x"FDFEC8", x"FE079B", x"FE105B", x"FE1908",
    x"FE21A1", x"FE2A26", x"FE3298", x"FE3AF7", x"FE4342", x"FE4B7A", x"FE539E", x"FE5BAF",
    x"FE63AC", x"FE6B95", x"FE736C", x"FE7B2E", x"FE82DD", x"FE8A79", x"FE9201", x"FE9976",
    x"FEA0D7", x"FEA824", x"FEAF5E", x"FEB685", x"FEBD98", x"FEC497", x"FECB83", x"FED25B",
    x"FED91F", x"FEDFD0", x"FEE66E", x"FEECF8", x"FEF36E", x"FEF9D1", x"FF0020", x"FF065C",
    x"FF0C84", x"FF1298", x"FF1899", x"FF1E86", x"FF245F", x"FF2A25", x"FF2FD7", x"FF3576",
    x"FF3B01", x"FF4078", x"FF45DC", x"FF4B2C", x"FF5069", x"FF5592", x"FF5AA7", x"FF5FA8",
    x"FF6496", x"FF6971", x"FF6E37", x"FF72EA", x"FF7789", x"FF7C15", x"FF808D", x"FF84F1",
    x"FF8942", x"FF8D7F", x"FF91A8", x"FF95BD", x"FF99BF", x"FF9DAD", x"FFA188", x"FFA54F",
    x"FFA902", x"FFACA1", x"FFB02D", x"FFB3A5", x"FFB709", x"FFBA5A", x"FFBD97", x"FFC0C0",
    x"FFC3D5", x"FFC6D7", x"FFC9C5", x"FFCC9F", x"FFCF66", x"FFD219", x"FFD4B8", x"FFD743",
    x"FFD9BB", x"FFDC1F", x"FFDE6F", x"FFE0AC", x"FFE2D5", x"FFE4EA", x"FFE6EB", x"FFE8D9",
    x"FFEAB2", x"FFEC79", x"FFEE2B", x"FFEFCA", x"FFF155", x"FFF2CC", x"FFF42F", x"FFF57F",
    x"FFF6BB", x"FFF7E3", x"FFF8F7", x"FFF9F8", x"FFFAE5", x"FFFBBE", x"FFFC84", x"FFFD36",
    x"FFFDD4", x"FFFE5E", x"FFFED4", x"FFFF37", x"FFFF86", x"FFFFC1", x"FFFFE9", x"FFFFFD" ); -- First 2048 samples here

    signal internal_addr0, internal_addr1, internal_addr2 : integer range 0 to 2047;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            -- Mirror logic: if MSB is 1, we are in the second half
            if addr0(11) = '0' then
                internal_addr0 <= to_integer(unsigned(addr0));
            else
                -- Subtract from max index to mirror the first half
                internal_addr0 <= 4095 - to_integer(unsigned(addr0));
            end if;
            
            data0 <= ROM(internal_addr0);
            
            -- Mirror logic: if MSB is 1, we are in the second half
            if addr1(11) = '0' then
                internal_addr1 <= to_integer(unsigned(addr1));
            else
                -- Subtract from max index to mirror the first half
                internal_addr1 <= 4095 - to_integer(unsigned(addr1));
            end if;
            
            data1 <= ROM(internal_addr1);
            
            -- Mirror logic: if MSB is 1, we are in the second half
            if addr2(11) = '0' then
                internal_addr2 <= to_integer(unsigned(addr2));
            else
                -- Subtract from max index to mirror the first half
                internal_addr2 <= 4095 - to_integer(unsigned(addr2));
            end if;
            
            data2 <= ROM(internal_addr2);
            
        end if;
    end process;

end RTL;
