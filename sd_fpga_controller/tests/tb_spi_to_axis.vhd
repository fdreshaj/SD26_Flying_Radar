library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_spi_to_axis is
  generic (mode : natural := 0; half_period_ns : positive := 10);
end entity;

architecture test of tb_spi_to_axis is
  function mode_bit(value : natural) return std_logic is
  begin
    if value = 0 then return '0'; else return '1'; end if;
  end function;
  constant polarity : std_logic := mode_bit(mode / 2);
  constant phase : std_logic := mode_bit(mode mod 2);
  constant half_period : time := half_period_ns * 1 ns;
  signal clk : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal sclk : std_logic := polarity;
  signal ss_n : std_logic := '1';
  signal mosi, miso : std_logic := '0';
  signal tx_data, rx_data : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_valid, tx_ready, rx_valid, rx_ready : std_logic := '0';
  signal overflow, underrun : std_logic;
  signal received : natural := 0;
  signal checking : boolean := false;
  signal stall_pattern : boolean := false;
  signal force_stall : boolean := false;
  signal stream_feed : boolean := false;
  signal stream_sent : natural range 0 to 256 := 0;
  signal overflow_check : boolean := false;
  signal overflow_base : natural := 0;
  signal selected_tx_data : std_logic_vector(7 downto 0);
  signal selected_tx_valid : std_logic;
begin
  selected_tx_data <= std_logic_vector(to_unsigned((stream_sent * 17 + 3) mod 256, 8))
                     when stream_feed else tx_data;
  selected_tx_valid <= '1' when stream_feed and stream_sent < 256 else
                       '0' when stream_feed else tx_valid;
  clk <= not clk after 5 ns;
  dut : entity work.spi_slave_to_axis
    generic map (cpol => polarity, cpha => phase, fifo_address_bits => 3)
    port map (
      aclk => clk, aresetn => reset_n, spi_sclk => sclk, spi_ss_n => ss_n,
      spi_mosi => mosi, spi_miso => miso,
      m_axis_tdata => rx_data, m_axis_tvalid => rx_valid, m_axis_tready => rx_ready,
      s_axis_tdata => selected_tx_data, s_axis_tvalid => selected_tx_valid, s_axis_tready => tx_ready,
      rx_overflow => overflow, tx_underrun => underrun
    );

  process(clk)
    variable cycle : natural := 0;
    variable stalled : boolean := false;
    variable held : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        received <= 0;
        stalled := false;
        rx_ready <= '0';
        cycle := 0;
      else
        if stalled then
          assert rx_valid = '1' and rx_data = held
            report "AXI data/valid changed during backpressure" severity failure;
        end if;
        stalled := rx_valid = '1' and rx_ready = '0';
        held := rx_data;
        if rx_valid = '1' and rx_ready = '1' then
          if checking then
            assert rx_data = std_logic_vector(to_unsigned((received * 13 + 9) mod 256, 8))
              report "RX byte ordering/content mismatch at " & integer'image(received) severity failure;
          elsif overflow_check then
            assert rx_data = std_logic_vector(to_unsigned(received - overflow_base, 8))
              report "Overflow corrupted previously queued data" severity failure;
          end if;
          received <= received + 1;
        end if;
        cycle := cycle + 1;
        if force_stall or (stall_pattern and cycle mod 11 < 7) then
          rx_ready <= '0';
        else
          rx_ready <= '1';
        end if;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        stream_sent <= 0;
      elsif stream_feed and stream_sent < 256 and tx_ready = '1' then
        stream_sent <= stream_sent + 1;
      end if;
    end if;
  end process;

  process
    procedure idle_clocks(count : positive) is
    begin
      wait for 0 ns;
      assert ss_n = '1' severity failure;
      for i in 1 to count loop
        wait for half_period;
        sclk <= not polarity;
        wait for half_period;
        sclk <= polarity;
      end loop;
      wait for half_period;
    end procedure;

    procedure enqueue(value : natural) is
    begin
      wait until falling_edge(clk);
      tx_data <= std_logic_vector(to_unsigned(value mod 256, 8));
      tx_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when tx_ready = '1';
      end loop;
      wait until falling_edge(clk);
      tx_valid <= '0';
    end procedure;

    procedure exchange(value : natural; expected : natural; late_tx : integer := -1) is
      variable outgoing, incoming : std_logic_vector(7 downto 0);
    begin
      outgoing := std_logic_vector(to_unsigned(value mod 256, 8));
      for bit_number in 7 downto 0 loop
        if bit_number = 4 and late_tx >= 0 then
          enqueue(late_tx);
        end if;
        if phase = '0' then mosi <= outgoing(bit_number); end if;
        wait for half_period - 1 ns;
        sclk <= not polarity;
        if phase = '1' then mosi <= outgoing(bit_number); end if;
        wait for 1 ns;
        if phase = '0' then incoming(bit_number) := miso; end if;
        wait for half_period - 1 ns;
        sclk <= polarity;
        wait for 1 ns;
        if phase = '1' then incoming(bit_number) := miso; end if;
      end loop;
      assert incoming = std_logic_vector(to_unsigned(expected mod 256, 8))
        report "MISO mismatch: expected " & integer'image(expected mod 256) &
               " got " & integer'image(to_integer(unsigned(incoming))) severity failure;
    end procedure;

    variable started : time;
    variable elapsed : time;
  begin
    wait for 33 ns;
    reset_n <= '1';
    wait for 60 ns;
    idle_clocks(5);
    checking <= true;
    stall_pattern <= true;
    stream_feed <= true;
    wait until stream_sent = 8;
    idle_clocks(5);
    ss_n <= '0';
    started := now;
    for i in 0 to 255 loop
      exchange(i * 13 + 9, i * 17 + 3);
    end loop;
    elapsed := now - started;
    assert elapsed <= 64 us report "Sustained full-duplex throughput below 32 Mbit/s" severity failure;
    report "Continuous full-duplex: 2048 bits/direction in " & time'image(elapsed);
    wait for half_period;
    ss_n <= '1';
    wait for 300 ns;
    assert received = 256 and stream_sent = 256 and overflow = '0' and underrun = '0'
      report "Continuous full-duplex streaming failed" severity failure;
    stream_feed <= false;
    reset_n <= '0';
    wait for 33 ns;
    reset_n <= '1';
    wait for 60 ns;
    idle_clocks(5);
    for group_number in 0 to 7 loop
      for i in 0 to 7 loop
        enqueue((group_number * 8 + i) * 17 + 3);
      end loop;
      assert tx_ready = '0' report "TX FIFO did not backpressure at capacity" severity failure;
      idle_clocks(5);
      ss_n <= '0';
      started := now;
      for i in 0 to 7 loop
        exchange((group_number * 8 + i) * 13 + 9, (group_number * 8 + i) * 17 + 3);
      end loop;
      elapsed := now - started;
      assert elapsed <= 2 us report "SPI throughput below 32 Mbit/s" severity failure;
      report "Bridge mode " & integer'image(mode) & ": 64 payload bits in " & time'image(elapsed);
      wait for half_period;
      ss_n <= '1';
      wait for 200 ns;
      assert overflow = '0' and underrun = '0'
        report "Unexpected bridge error" severity failure;
    end loop;
    wait for 300 ns;
    assert received = 64 report "Not all RX bytes delivered" severity failure;
    checking <= false;
    stall_pattern <= false;

    -- A partial word must neither publish RX data nor consume TX data.
    enqueue(16#A5#);
    idle_clocks(5);
    ss_n <= '0';
    for i in 1 to 3 loop
      wait for half_period;
      sclk <= not polarity;
      wait for half_period;
      sclk <= polarity;
    end loop;
    wait for half_period;
    ss_n <= '1';
    idle_clocks(5);
    ss_n <= '0';
    exchange(16#5A#, 16#A5#);
    wait for half_period;
    ss_n <= '1';
    wait for 200 ns;
    assert received = 65 report "Partial RX word was not discarded" severity failure;

    -- Empty TX supplies zeros and reports a sticky underrun.
    idle_clocks(5);
    ss_n <= '0';
    exchange(16#12#, 0, 16#96#);
    exchange(16#34#, 16#96#);
    wait for half_period;
    ss_n <= '1';
    wait for 100 ns;
    assert underrun = '1' report "Missing TX underrun indication" severity failure;

    -- No SPI backpressure exists: fill RX, preserve queued data, drop newest.
    overflow_base <= received;
    overflow_check <= true;
    force_stall <= true;
    wait for 100 ns;
    idle_clocks(5);
    ss_n <= '0';
    for i in 0 to 11 loop
      exchange(i, 0);
    end loop;
    wait for half_period;
    ss_n <= '1';
    wait for 100 ns;
    assert overflow = '1' report "Missing RX overflow indication" severity failure;
    force_stall <= false;
    wait for 1500 ns;
    assert received = overflow_base + 8
      report "FIFO overflow did not preserve exactly eight queued words" severity failure;
    overflow_check <= false;

    -- Reset also flushes queued data and works while the SPI clock is stopped.
    force_stall <= true;
    wait for 100 ns;
    enqueue(16#C3#);
    idle_clocks(5);
    ss_n <= '0';
    exchange(16#55#, 16#C3#);
    enqueue(16#42#);
    for i in 1 to 3 loop
      wait for half_period;
      sclk <= not polarity;
      wait for half_period;
      sclk <= polarity;
    end loop;
    reset_n <= '0';
    ss_n <= '1';
    wait for 27 ns;
    assert overflow = '0' and underrun = '0' and miso = 'Z' severity failure;
    force_stall <= false;
    reset_n <= '1';
    idle_clocks(5);
    wait for 100 ns;
    assert rx_valid = '0' report "FIFO not empty after reset" severity failure;
    enqueue(16#C3#);
    idle_clocks(5);
    ss_n <= '0';
    exchange(16#3C#, 16#C3#);
    wait for half_period;
    ss_n <= '1';
    wait for 200 ns;
    assert received = 1 and overflow = '0' and underrun = '0'
      report "Post-reset recovery failed" severity failure;
    report "tb_spi_to_axis PASS";
    stop;
    wait;
  end process;

  process
  begin
    wait for 1 ms;
    assert false report "Bridge watchdog expired" severity failure;
  end process;
end architecture;
