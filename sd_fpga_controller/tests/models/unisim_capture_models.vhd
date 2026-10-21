-- Functional-only substitutes for GHDL. Never import into a Vivado project.
-- These do not model device timing, jitter, metastability, or MMCM dynamics.
library ieee;
use ieee.std_logic_1164.all;

package vcomponents is
  component IBUFDS is
    generic (DIFF_TERM : boolean := false; IOSTANDARD : string := "DEFAULT");
    port (I, IB : in std_logic; O : out std_logic);
  end component;
  component BUFG is
    port (I : in std_logic; O : out std_logic);
  end component;
  component IDDR is
    generic (DDR_CLK_EDGE : string := "OPPOSITE_EDGE"; SRTYPE : string := "SYNC");
    port (C, CE, D, R, S : in std_logic; Q1, Q2 : out std_logic);
  end component;
  component MMCME2_BASE is
    generic (
      CLKIN1_PERIOD : real := 0.0; CLKFBOUT_MULT_F : real := 5.0;
      DIVCLK_DIVIDE : integer := 1; CLKOUT0_DIVIDE_F : real := 1.0;
      CLKOUT0_PHASE : real := 0.0; BANDWIDTH : string := "OPTIMIZED";
      STARTUP_WAIT : boolean := false
    );
    port (
      CLKIN1, CLKFBIN, PWRDWN, RST : in std_logic;
      CLKFBOUT, CLKFBOUTB, CLKOUT0, CLKOUT0B, CLKOUT1, CLKOUT1B,
      CLKOUT2, CLKOUT2B, CLKOUT3, CLKOUT3B, CLKOUT4, CLKOUT5, CLKOUT6,
      LOCKED : out std_logic
    );
  end component;
end package;

library ieee;
use ieee.std_logic_1164.all;
entity IBUFDS is
  generic (DIFF_TERM : boolean := false; IOSTANDARD : string := "DEFAULT");
  port (I, IB : in std_logic; O : out std_logic);
end entity;
architecture functional of IBUFDS is
begin
  O <= I;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity BUFG is
  port (I : in std_logic; O : out std_logic);
end entity;
architecture functional of BUFG is
begin
  O <= I;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity IDDR is
  generic (DDR_CLK_EDGE : string := "OPPOSITE_EDGE"; SRTYPE : string := "SYNC");
  port (C, CE, D, R, S : in std_logic; Q1, Q2 : out std_logic);
end entity;
architecture functional of IDDR is
  signal rise, fall : std_logic := '0';
begin
  assert DDR_CLK_EDGE = "SAME_EDGE_PIPELINED" and SRTYPE = "ASYNC"
    report "Test IDDR supports only SAME_EDGE_PIPELINED/ASYNC" severity failure;
  process(C, R, S)
  begin
    if R = '1' then
      rise <= '0'; Q1 <= '0'; Q2 <= '0';
    elsif S = '1' then
      rise <= '1'; Q1 <= '1'; Q2 <= '1';
    elsif rising_edge(C) and CE = '1' then
      rise <= D; Q1 <= rise; Q2 <= fall;
    end if;
  end process;
  process(C, R, S)
  begin
    if R = '1' then fall <= '0';
    elsif S = '1' then fall <= '1';
    elsif falling_edge(C) and CE = '1' then fall <= D;
    end if;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity MMCME2_BASE is
  generic (
    CLKIN1_PERIOD : real := 0.0; CLKFBOUT_MULT_F : real := 5.0;
    DIVCLK_DIVIDE : integer := 1; CLKOUT0_DIVIDE_F : real := 1.0;
    CLKOUT0_PHASE : real := 0.0; BANDWIDTH : string := "OPTIMIZED";
    STARTUP_WAIT : boolean := false
  );
  port (
    CLKIN1, CLKFBIN, PWRDWN, RST : in std_logic;
    CLKFBOUT, CLKFBOUTB, CLKOUT0, CLKOUT0B, CLKOUT1, CLKOUT1B,
    CLKOUT2, CLKOUT2B, CLKOUT3, CLKOUT3B, CLKOUT4, CLKOUT5, CLKOUT6,
    LOCKED : out std_logic
  );
end entity;
architecture functional of MMCME2_BASE is
  signal cycles : natural range 0 to 16 := 0;
  signal shifted : std_logic := '0';
begin
  assert CLKFBOUT_MULT_F = 10.0 and DIVCLK_DIVIDE = 1 and CLKOUT0_DIVIDE_F = 10.0
    report "Test MMCM supports only 1:1 clock ratio" severity failure;
  shifted <= transport CLKIN1 after (CLKIN1_PERIOD * CLKOUT0_PHASE / 360.0) * 1 ns;
  CLKOUT0 <= shifted;
  CLKOUT0B <= not shifted;
  CLKFBOUT <= CLKIN1;
  CLKFBOUTB <= not CLKIN1;
  CLKOUT1 <= '0'; CLKOUT1B <= '1'; CLKOUT2 <= '0'; CLKOUT2B <= '1';
  CLKOUT3 <= '0'; CLKOUT3B <= '1'; CLKOUT4 <= '0'; CLKOUT5 <= '0'; CLKOUT6 <= '0';
  LOCKED <= '1' when cycles = 16 else '0';
  process(CLKIN1, RST, PWRDWN)
  begin
    if RST = '1' or PWRDWN = '1' then cycles <= 0;
    elsif rising_edge(CLKIN1) then
      if cycles < 16 then cycles <= cycles + 1; end if;
    end if;
  end process;
end architecture;
