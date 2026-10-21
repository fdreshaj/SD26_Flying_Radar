library ieee;
use ieee.std_logic_1164.all;
library unisim;
use unisim.vcomponents.all;

entity ad9284_lvds_rx is
  generic (
    rising_is_a : boolean := true;
    pair_previous_falling : boolean := false;
    dco_period_ns : real := 10.0;
    capture_phase_degrees : real := 90.0;
    differential_termination : boolean := false
  );
  port (
    reset_n : in std_logic;
    adc_dco_p, adc_dco_n : in std_logic;
    adc_data_p, adc_data_n : in std_logic_vector(7 downto 0);
    sample_clk, locked, sample_valid : out std_logic;
    sample_a, sample_b : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of ad9284_lvds_rx is
  signal dco, feedback, feedback_buffered, shifted, capture_clk, clock_locked : std_logic;
  signal data, rising_data, falling_data, previous_falling, paired_falling : std_logic_vector(7 downto 0);
  signal rx_reset, mmcm_reset, iddr_reset : std_logic;
  signal warmup : std_logic_vector(3 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of warmup : signal is "TRUE";
begin
  mmcm_reset <= not reset_n;
  iddr_reset <= not warmup(1);
  assert dco_period_ns >= 9.0 and dco_period_ns <= 12.0
    report "Receiver MMCM settings support DCO periods 9..12 ns; regenerate clocking for other rates" severity failure;
  clock_input : IBUFDS
    generic map (DIFF_TERM => differential_termination, IOSTANDARD => "LVDS_25")
    port map (I => adc_dco_p, IB => adc_dco_n, O => dco);
  phase_clock : MMCME2_BASE
    generic map (
      CLKIN1_PERIOD => dco_period_ns,
      CLKFBOUT_MULT_F => 10.0, DIVCLK_DIVIDE => 1,
      CLKOUT0_DIVIDE_F => 10.0, CLKOUT0_PHASE => capture_phase_degrees,
      BANDWIDTH => "OPTIMIZED", STARTUP_WAIT => false
    )
    port map (
      CLKIN1 => dco, CLKFBIN => feedback_buffered,
      CLKFBOUT => feedback, CLKFBOUTB => open,
      CLKOUT0 => shifted, CLKOUT0B => open,
      CLKOUT1 => open, CLKOUT1B => open, CLKOUT2 => open, CLKOUT2B => open,
      CLKOUT3 => open, CLKOUT3B => open, CLKOUT4 => open, CLKOUT5 => open,
      CLKOUT6 => open, LOCKED => clock_locked, PWRDWN => '0', RST => mmcm_reset
    );
  feedback_clock : BUFG port map (I => feedback, O => feedback_buffered);
  sample_clock_buffer : BUFG port map (I => shifted, O => capture_clk);
  sample_clk <= capture_clk;
  locked <= clock_locked;
  rx_reset <= not reset_n or not clock_locked;

  process(capture_clk, rx_reset)
  begin
    if rx_reset = '1' then
      warmup <= (others => '0');
    elsif rising_edge(capture_clk) then
      warmup <= warmup(2 downto 0) & '1';
    end if;
  end process;
  sample_valid <= warmup(3);

  bits : for bit_index in 0 to 7 generate
    data_input : IBUFDS
      generic map (DIFF_TERM => differential_termination, IOSTANDARD => "LVDS_25")
      port map (I => adc_data_p(bit_index), IB => adc_data_n(bit_index), O => data(bit_index));
    capture_register : IDDR
      generic map (DDR_CLK_EDGE => "SAME_EDGE_PIPELINED", SRTYPE => "ASYNC")
      port map (
        C => capture_clk, CE => '1', D => data(bit_index),
        R => iddr_reset, S => '0',
        Q1 => rising_data(bit_index), Q2 => falling_data(bit_index)
      );
  end generate;
  process(capture_clk, rx_reset)
  begin
    if rx_reset = '1' then
      previous_falling <= (others => '0');
    elsif rising_edge(capture_clk) then
      previous_falling <= falling_data;
    end if;
  end process;
  paired_falling <= previous_falling when pair_previous_falling else falling_data;
  sample_a <= rising_data when rising_is_a else paired_falling;
  sample_b <= paired_falling when rising_is_a else rising_data;
end architecture;
