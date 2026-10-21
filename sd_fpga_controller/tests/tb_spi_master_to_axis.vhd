library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_spi_master_to_axis is
  generic (mode : natural := 0; divider : positive := 1);
end entity;

architecture test of tb_spi_master_to_axis is
  function mode_bit(value : natural) return std_logic is
  begin
    if value = 0 then return '0'; else return '1'; end if;
  end function;
  constant polarity : std_logic := mode_bit(mode / 2);
  constant phase : std_logic := mode_bit(mode mod 2);
  signal clk : std_logic := '0';
  signal reset_n, tx_valid, tx_ready, rx_valid, rx_ready : std_logic := '0';
  signal sclk, ss_n, mosi, miso : std_logic;
  signal tx_data, rx_data : std_logic_vector(7 downto 0) := (others => '0');
  signal accepted, delivered : natural := 0;
  signal stalls : boolean := false;
begin
  clk <= not clk after 5 ns;
  dut : entity work.spi_master_to_axis
    generic map (cpol => polarity, cpha => phase, clk_divider => divider)
    port map (
      aclk => clk, aresetn => reset_n, spi_sclk => sclk, spi_ss_n => ss_n,
      spi_mosi => mosi, spi_miso => miso,
      s_axis_tdata => tx_data, s_axis_tvalid => tx_valid, s_axis_tready => tx_ready,
      m_axis_tdata => rx_data, m_axis_tvalid => rx_valid, m_axis_tready => rx_ready
    );

  -- Independent external-slave model: samples MOSI, returns different bytes.
  process
    variable incoming, outgoing : std_logic_vector(7 downto 0);
    variable word : natural := 0;
  begin
    miso <= '0';
    wait until ss_n = '0';
    outgoing := std_logic_vector(to_unsigned((word * 29 + 7) mod 256, 8));
    miso <= outgoing(7);
    for bit_number in 7 downto 0 loop
      wait until sclk'event or reset_n = '0';
      exit when reset_n = '0';
      if phase = '0' then
        incoming(bit_number) := mosi;
      else
        miso <= outgoing(bit_number);
      end if;
      wait until sclk'event or reset_n = '0';
      exit when reset_n = '0';
      if phase = '1' then
        incoming(bit_number) := mosi;
      elsif bit_number > 0 then
        miso <= outgoing(bit_number - 1);
      end if;
    end loop;
    if reset_n = '0' then
      word := 0;
    else
      assert incoming = std_logic_vector(to_unsigned((word * 13 + 9) mod 256, 8))
        report "External slave received incorrect MOSI byte" severity failure;
      wait until ss_n = '1';
      word := word + 1;
    end if;
  end process;

  process(clk)
    variable held : std_logic_vector(7 downto 0);
    variable stalled : boolean := false;
    variable cycle : natural := 0;
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        accepted <= 0;
        delivered <= 0;
        rx_ready <= '0';
        stalled := false;
        cycle := 0;
      else
        cycle := cycle + 1;
        if stalls and cycle mod 101 < 70 then rx_ready <= '0';
        else rx_ready <= '1'; end if;
        if stalled then
          assert rx_valid = '1' and rx_data = held
            report "Master AXI output changed while stalled" severity failure;
          assert ss_n = '1' and (rx_ready = '1' or tx_ready = '0')
            report "Master started without available result storage" severity failure;
        end if;
        held := rx_data;
        stalled := rx_valid = '1' and rx_ready = '0';
        if tx_valid = '1' and tx_ready = '1' then accepted <= accepted + 1; end if;
        if rx_valid = '1' and rx_ready = '1' then
          assert rx_data = std_logic_vector(to_unsigned((delivered * 29 + 7) mod 256, 8))
            report "AXI receive byte mismatch" severity failure;
          delivered <= delivered + 1;
        end if;
      end if;
    end if;
  end process;

  process
    variable started : time;
    variable elapsed : time;
  begin
    wait for 33 ns;
    reset_n <= '1';
    wait until falling_edge(clk);
    started := now;
    for word in 0 to 127 loop
      tx_data <= std_logic_vector(to_unsigned((word * 13 + 9) mod 256, 8));
      tx_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when tx_ready = '1';
      end loop;
      wait until falling_edge(clk);
      if word = 63 then
        tx_valid <= '0';
        wait until delivered = 64;
        elapsed := now - started;
        if divider = 1 then
          assert elapsed <= 16 us
            report "Master AXI bridge below 32 Mbit/s" severity failure;
        end if;
        report "Master bridge: 512 bits in " & time'image(elapsed);
        stalls <= true;
        wait for 200 ns;
        wait until falling_edge(clk);
      end if;
    end loop;
    tx_valid <= '0';
    wait until delivered = 128;
    assert accepted = 128 severity failure;
    wait for 200 ns;
    assert ss_n = '1' and sclk = polarity and rx_valid = '0'
      report "Master did not remain idle without TX data" severity failure;

    -- Abort a word; reset must suppress a stale result and deassert CS.
    tx_valid <= '1';
    wait until ss_n = '0';
    wait until sclk'event;
    reset_n <= '0';
    tx_valid <= '0';
    wait for 1 ns;
    assert ss_n = '1' and rx_valid = '0' and tx_ready = '0' severity failure;
    wait for 32 ns;
    reset_n <= '1';
    wait for 100 ns;
    assert rx_valid = '0' and ss_n = '1' and sclk = polarity
      report "Stale result after reset" severity failure;
    wait until falling_edge(clk);
    tx_data <= std_logic_vector(to_unsigned(9, 8));
    tx_valid <= '1';
    loop
      wait until rising_edge(clk);
      exit when tx_ready = '1';
    end loop;
    wait until falling_edge(clk);
    tx_valid <= '0';
    wait until delivered = 1;
    assert accepted = 1 report "Post-reset transaction count mismatch" severity failure;
    report "tb_spi_master_to_axis PASS";
    stop;
    wait;
  end process;

  process
  begin
    wait for 1 ms;
    assert false report "Master bridge watchdog expired" severity failure;
  end process;
end architecture;
