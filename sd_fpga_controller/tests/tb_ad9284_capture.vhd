library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_ad9284_capture is
  generic (pairs : positive := 1024; sample_half_ns : positive := 5);
end entity;

architecture test of tb_ad9284_capture is
  signal clk, sample_clk : std_logic := '0';
  signal reset_n, trigger, ready, busy, done, fault : std_logic := '0';
  signal locked, sample_valid : std_logic := '1';
  signal a, b : std_logic_vector(7 downto 0);
  signal data : std_logic_vector(31 downto 0);
  signal valid, last, take : std_logic := '0';
  signal sample_number : natural := 0;
  signal received, packets, done_count : natural := 0;
  signal force_stall : boolean := true;
begin
  clk <= not clk after 5 ns;
  sample_clk <= not sample_clk after sample_half_ns * 1 ns;
  a <= std_logic_vector(to_unsigned(sample_number mod 256, 8));
  b <= std_logic_vector(to_unsigned(255 - sample_number mod 256, 8));
  process(sample_clk)
  begin
    if falling_edge(sample_clk) then sample_number <= sample_number + 1; end if;
  end process;
  dut : entity work.ad9284_capture
    generic map (capture_pairs => pairs)
    port map (
      aclk => clk, aresetn => reset_n, trigger => trigger,
      ready => ready, busy => busy, done => done, capture_fault => fault,
      sample_clk => sample_clk, sample_locked => locked, sample_valid => sample_valid,
      sample_a => a, sample_b => b, m_axis_tdata => data,
      m_axis_tvalid => valid, m_axis_tlast => last, m_axis_tready => take
    );
  process(clk)
    variable beat, first_a, expected_a, cycle : natural := 0;
    variable held : std_logic_vector(31 downto 0);
    variable held_last : std_logic;
    variable stalled : boolean := false;
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        take <= '0';
        received <= 0;
        packets <= 0;
        done_count <= 0;
        beat := 0;
        stalled := false;
      else
        cycle := cycle + 1;
        if force_stall or cycle mod 13 < 8 then take <= '0';
        else take <= '1'; end if;
        if stalled then
          assert valid = '1' and data = held and last = held_last
            report "ADC AXI payload changed during stall" severity failure;
        end if;
        stalled := valid = '1' and take = '0';
        held := data;
        held_last := last;
        if done = '1' then done_count <= done_count + 1; end if;
        if valid = '1' and take = '1' then
          if beat = 0 then first_a := to_integer(unsigned(data(7 downto 0))); end if;
          expected_a := (first_a + beat * 2) mod 256;
          assert data(7 downto 0) = std_logic_vector(to_unsigned(expected_a, 8)) and
                 data(15 downto 8) = std_logic_vector(to_unsigned(255 - expected_a, 8)) and
                 data(23 downto 16) = std_logic_vector(to_unsigned((expected_a + 1) mod 256, 8)) and
                 data(31 downto 24) = std_logic_vector(to_unsigned(255 - (expected_a + 1) mod 256, 8))
            report "ADC capture packing/channel/continuity mismatch" severity failure;
          received <= received + 1;
          if beat = pairs / 2 - 1 then
            assert last = '1' report "Missing capture TLAST" severity failure;
            packets <= packets + 1;
            beat := 0;
          else
            assert last = '0' report "Early capture TLAST" severity failure;
            beat := beat + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  process
    procedure pulse_trigger is
    begin
      trigger <= '1';
      wait for 70 ns;
      trigger <= '0';
      wait for 70 ns;
    end procedure;
  begin
    wait for 37 ns;
    reset_n <= '1';
    wait until ready = '1';
    pulse_trigger;
    assert busy = '1' and ready = '0' severity failure;
    pulse_trigger;
    wait until valid = '1';
    wait for 500 ns;
    assert received = 0 and busy = '1' report "Capture did not buffer under AXI stall" severity failure;
    pulse_trigger;
    force_stall <= false;
    trigger <= '1';
    wait until packets = 1;
    wait for 200 ns;
    assert ready = '1' and busy = '0' and received = pairs / 2 and done_count = 1 severity failure;
    trigger <= '0';
    wait for 70 ns;
    pulse_trigger;
    wait until packets = 2;
    wait for 200 ns;
    assert received = pairs and done_count = 2 and fault = '0'
      report "Repeated capture failed or busy trigger was queued" severity failure;

    -- Reset discards an in-progress acquisition.
    pulse_trigger;
    reset_n <= '0';
    wait for 31 ns;
    assert valid = '0' and busy = '0' and done = '0' severity failure;
    reset_n <= '1';
    wait until ready = '1';
    pulse_trigger;
    wait until packets = 1;
    wait for 200 ns;
    assert fault = '0' severity failure;

    -- Reset while a complete capture is blocked at its AXI output.
    force_stall <= true;
    pulse_trigger;
    wait until valid = '1';
    wait for 100 ns;
    reset_n <= '0';
    wait for 31 ns;
    assert valid = '0' and last = '0' and busy = '0' severity failure;
    reset_n <= '1';
    force_stall <= false;
    wait until ready = '1';

    -- Clock lock loss during acquisition must not publish a corrupt packet.
    pulse_trigger;
    locked <= '0';
    sample_valid <= '0';
    wait for 200 ns;
    assert fault = '1' and busy = '1' and ready = '0' and valid = '0'
      report "Capture did not latch clock-loss fault" severity failure;
    locked <= '1';
    wait for 200 ns;
    assert fault = '1' and valid = '0' report "Capture fault cleared without reset" severity failure;
    reset_n <= '0';
    wait for 31 ns;
    assert fault = '0' severity failure;
    report "tb_ad9284_capture PASS";
    stop;
    wait;
  end process;
  process
  begin
    wait for 1 ms;
    assert false report "ADC capture watchdog expired" severity failure;
  end process;
end architecture;
