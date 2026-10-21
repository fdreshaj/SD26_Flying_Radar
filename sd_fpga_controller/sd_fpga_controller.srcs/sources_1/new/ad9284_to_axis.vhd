library ieee;
use ieee.std_logic_1164.all;

entity ad9284_to_axis is
  generic (
    capture_pairs : positive := 1024;
    rising_is_a : boolean := true;
    pair_previous_falling : boolean := false;
    capture_phase_degrees : real := 90.0;
    differential_termination : boolean := false
  );
  port (
    aclk, aresetn : in std_logic;
    adc_dco_p, adc_dco_n : in std_logic;
    adc_data_p, adc_data_n : in std_logic_vector(7 downto 0);
    trigger : in std_logic;
    ready, busy, done, capture_fault, adc_locked : out std_logic;
    m_axis_tdata : out std_logic_vector(31 downto 0);
    m_axis_tvalid, m_axis_tlast : out std_logic;
    m_axis_tready : in std_logic
  );
end entity;

architecture rtl of ad9284_to_axis is
  signal sample_clk, sample_valid, locked : std_logic;
  signal sample_a, sample_b : std_logic_vector(7 downto 0);
  signal lock_sync : std_logic_vector(1 downto 0) := "00";
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of lock_sync : signal is "TRUE";
begin
  receiver : entity work.ad9284_lvds_rx
    generic map (
      rising_is_a => rising_is_a, pair_previous_falling => pair_previous_falling,
      capture_phase_degrees => capture_phase_degrees,
      differential_termination => differential_termination
    )
    port map (
      reset_n => aresetn, adc_dco_p => adc_dco_p, adc_dco_n => adc_dco_n,
      adc_data_p => adc_data_p, adc_data_n => adc_data_n,
      sample_clk => sample_clk, locked => locked, sample_valid => sample_valid,
      sample_a => sample_a, sample_b => sample_b
    );
  capture : entity work.ad9284_capture
    generic map (capture_pairs => capture_pairs)
    port map (
      aclk => aclk, aresetn => aresetn, trigger => trigger,
      ready => ready, busy => busy, done => done, capture_fault => capture_fault,
      sample_clk => sample_clk, sample_locked => locked, sample_valid => sample_valid,
      sample_a => sample_a, sample_b => sample_b,
      m_axis_tdata => m_axis_tdata, m_axis_tvalid => m_axis_tvalid,
      m_axis_tlast => m_axis_tlast, m_axis_tready => m_axis_tready
    );
  process(aclk, aresetn)
  begin
    if aresetn = '0' then
      lock_sync <= "00";
    elsif rising_edge(aclk) then
      lock_sync <= lock_sync(0) & locked;
    end if;
  end process;
  adc_locked <= lock_sync(1);
end architecture;
