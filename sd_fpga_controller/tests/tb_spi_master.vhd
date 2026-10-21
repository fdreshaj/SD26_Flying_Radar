library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_spi_master is
  generic (width : positive := 8; divider : positive := 1);
end entity;

architecture test of tb_spi_master is
  signal clk : std_logic := '0';
  signal reset_n, enable, cpol, cpha, miso : std_logic := '0';
  signal sclk, ss_n, mosi, busy, done : std_logic;
  signal tx, rx : std_logic_vector(width - 1 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.spi_master
    generic map (data_length => width, clk_divider => divider)
    port map (
      clk => clk, reset_n => reset_n, enable => enable, cpol => cpol, cpha => cpha,
      miso => miso, sclk => sclk, ss_n => ss_n, mosi => mosi,
      busy => busy, tx => tx, rx => rx, done => done
    );

  process
    variable expected_tx, expected_rx : std_logic_vector(width - 1 downto 0);
    variable polarity, phase : std_logic;
    variable started : time;
    variable elapsed : time;
  begin
    wait for 27 ns;
    reset_n <= '1';
    for mode in 0 to 3 loop
      if mode >= 2 then polarity := '1'; else polarity := '0'; end if;
      if mode mod 2 = 1 then phase := '1'; else phase := '0'; end if;
      cpol <= polarity;
      cpha <= phase;
      started := now;
      for word in 0 to 63 loop
        expected_tx := std_logic_vector(to_unsigned((word * 37 + 81) mod 256, width));
        expected_rx := std_logic_vector(to_unsigned((word * 19 + 163) mod 256, width));
        wait until falling_edge(clk);
        tx <= expected_tx;
        enable <= '1';
        miso <= expected_rx(width - 1);
        wait until rising_edge(clk);
        wait for 1 ns;
        assert busy = '1' and ss_n = '0' severity failure;
        enable <= '0';
        for bit_number in width - 1 downto 0 loop
          wait until sclk'event;
          wait for 1 ns;
          assert sclk = not polarity and ss_n = '0'
            report "Incorrect leading edge" severity failure;
          if phase = '0' then
            assert mosi = expected_tx(bit_number)
              report "Master CPHA=0 MOSI mismatch" severity failure;
          else
            miso <= expected_rx(bit_number);
          end if;
          wait until sclk'event;
          wait for 1 ns;
          assert sclk = polarity and ss_n = '0'
            report "Incorrect trailing edge" severity failure;
          if phase = '1' then
            assert mosi = expected_tx(bit_number)
              report "Master CPHA=1 MOSI mismatch" severity failure;
          elsif bit_number > 0 then
            miso <= expected_rx(bit_number - 1);
          end if;
        end loop;
        wait until done = '1';
        wait for 1 ns;
        assert rx = expected_rx report "Master receive mismatch" severity failure;
        assert busy = '0' and ss_n = '1' and sclk = polarity severity failure;
      end loop;
      elapsed := now - started;
      if width = 8 and divider = 1 then
        assert elapsed <= 16 us report "Master sustained throughput below 32 Mbit/s" severity failure;
      end if;
      report "Master mode " & integer'image(mode) & ": 64 words in " & time'image(elapsed);
    end loop;

    wait until falling_edge(clk);
    enable <= '1';
    wait until ss_n = '0';
    wait until sclk'event;
    reset_n <= '0';
    wait for 1 ns;
    assert ss_n = '1' and busy = '0' and done = '0'
      report "Master reset did not abort transfer" severity failure;
    report "tb_spi_master PASS";
    stop;
    wait;
  end process;

  process
  begin
    wait for 1 ms;
    assert false report "Master watchdog expired" severity failure;
  end process;
end architecture;
