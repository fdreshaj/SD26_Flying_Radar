library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_ad9284_to_axis is
  generic (rising_is_a : boolean := true; pair_previous_falling : boolean := false);
end entity;

architecture test of tb_ad9284_to_axis is
  signal clk, dco : std_logic := '0';
  signal reset_n, trigger, ready, busy, done, fault, locked : std_logic := '0';
  signal wire_data : std_logic_vector(7 downto 0) := (others => '0');
  signal data : std_logic_vector(31 downto 0);
  signal valid, last, take : std_logic := '0';
  signal received : natural := 0;
  signal stalled_by_test : boolean := true;
begin
  clk <= not clk after 5 ns;
  -- Independent clocks at the same nominal frequency, with a phase offset.
  process
  begin
    wait for 1300 ps;
    loop
      dco <= '1'; wait for 5 ns;
      dco <= '0'; wait for 5 ns;
    end loop;
  end process;
  process
    variable number : natural := 0;
  begin
    wait until rising_edge(dco);
    if rising_is_a then
      wire_data <= std_logic_vector(to_unsigned(number mod 256, 8));
    else
      wire_data <= std_logic_vector(to_unsigned(255 - number mod 256, 8));
    end if;
    wait until falling_edge(dco);
    if pair_previous_falling then number := number + 1; end if;
    if rising_is_a then
      wire_data <= std_logic_vector(to_unsigned(255 - number mod 256, 8));
    else
      wire_data <= std_logic_vector(to_unsigned(number mod 256, 8));
    end if;
    if not pair_previous_falling then number := number + 1; end if;
  end process;
  dut : entity work.ad9284_to_axis
    generic map (rising_is_a => rising_is_a, pair_previous_falling => pair_previous_falling)
    port map (
      aclk => clk, aresetn => reset_n,
      adc_dco_p => dco, adc_dco_n => not dco,
      adc_data_p => wire_data, adc_data_n => not wire_data,
      trigger => trigger, ready => ready, busy => busy, done => done,
      capture_fault => fault, adc_locked => locked,
      m_axis_tdata => data, m_axis_tvalid => valid,
      m_axis_tlast => last, m_axis_tready => take
    );
  process(clk)
    variable first_a, expected_a, cycle : natural := 0;
    variable held : std_logic_vector(31 downto 0);
    variable held_last : std_logic;
    variable stalled : boolean := false;
  begin
    if rising_edge(clk) and reset_n = '1' then
      cycle := cycle + 1;
      if stalled_by_test or cycle mod 7 < 4 then take <= '0'; else take <= '1'; end if;
      if stalled then
        assert valid = '1' and data = held and last = held_last severity failure;
      end if;
      stalled := valid = '1' and take = '0';
      held := data;
      held_last := last;
      if valid = '1' and take = '1' then
        if received mod 512 = 0 then first_a := to_integer(unsigned(data(7 downto 0))); end if;
        expected_a := (first_a + received * 2) mod 256;
        assert data(7 downto 0) = std_logic_vector(to_unsigned(expected_a, 8)) and
               data(15 downto 8) = std_logic_vector(to_unsigned(255 - expected_a, 8)) and
               data(23 downto 16) = std_logic_vector(to_unsigned((expected_a + 1) mod 256, 8)) and
               data(31 downto 24) = std_logic_vector(to_unsigned(255 - (expected_a + 1) mod 256, 8))
          report "LVDS receiver/capture channel alignment mismatch" severity failure;
        if received mod 512 = 511 then assert last = '1' severity failure;
        else assert last = '0' severity failure; end if;
        received <= received + 1;
      end if;
    end if;
  end process;
  process
    variable started : time;
  begin
    wait for 37 ns;
    reset_n <= '1';
    wait until ready = '1';
    assert locked = '1' severity failure;
    started := now;
    trigger <= '1';
    wait for 70 ns;
    trigger <= '0';
    wait until valid = '1';
    assert now - started > 10240 ns and now - started < 11 us
      report "Capture did not acquire 1024 pairs at 100 MSamples/s" severity failure;
    wait for 500 ns;
    assert busy = '1' and received = 0 severity failure;
    stalled_by_test <= false;
    wait until done = '1';
    assert received = 512 and fault = '0' severity failure;
    wait for 100 ns;
    trigger <= '1';
    wait for 70 ns;
    trigger <= '0';
    wait until done = '1';
    assert received = 1024 and fault = '0' severity failure;
    report "tb_ad9284_to_axis PASS (functional primitive models only)";
    stop;
    wait;
  end process;
  process
  begin
    wait for 1 ms;
    assert false report "LVDS capture watchdog expired" severity failure;
  end process;
end architecture;
