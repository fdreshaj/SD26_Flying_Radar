library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_spi_master_to_axis_fifo is
  generic (mode : natural := 0);
end entity;

architecture test of tb_spi_master_to_axis_fifo is
  function mode_bit(value : natural) return std_logic is
  begin
    if value = 0 then return '0'; else return '1'; end if;
  end function;
  constant polarity : std_logic := mode_bit(mode / 2);
  constant phase : std_logic := mode_bit(mode mod 2);
  signal clk : std_logic := '0';
  signal reset_n, tx_valid, tx_ready, rx_valid, rx_last, rx_ready : std_logic := '0';
  signal sclk, ss_n, mosi, miso : std_logic;
  signal tx : std_logic_vector(7 downto 0);
  signal rx : std_logic_vector(31 downto 0);
  signal received, transfers : natural := 0;
  signal stalls : boolean := false;
begin
  clk <= not clk after 5 ns;
  dut : entity work.spi_master_to_axis_fifo
    generic map (cpol => polarity, cpha => phase)
    port map (
      aclk => clk, aresetn => reset_n,
      spi_sclk => sclk, spi_ss_n => ss_n, spi_mosi => mosi, spi_miso => miso,
      s_axis_tdata => tx, s_axis_tvalid => tx_valid, s_axis_tready => tx_ready,
      m_axis_tdata => rx, m_axis_tvalid => rx_valid,
      m_axis_tlast => rx_last, m_axis_tready => rx_ready
    );
  process
    variable word : natural := 0;
    variable incoming, outgoing : std_logic_vector(7 downto 0);
  begin
    miso <= '0';
    wait until ss_n = '0';
    outgoing := std_logic_vector(to_unsigned((word * 17 + 3) mod 256, 8));
    miso <= outgoing(7);
    for bit_number in 7 downto 0 loop
      wait until sclk'event;
      if phase = '0' then incoming(bit_number) := mosi;
      else miso <= outgoing(bit_number); end if;
      wait until sclk'event;
      if phase = '1' then incoming(bit_number) := mosi;
      elsif bit_number > 0 then miso <= outgoing(bit_number - 1); end if;
    end loop;
    assert incoming = std_logic_vector(to_unsigned(word mod 256, 8))
      report "FIFO SPI wrapper MOSI mismatch" severity failure;
    wait until ss_n = '1';
    word := word + 1;
    transfers <= word;
  end process;
  process(clk)
    variable cycle : natural := 0;
    variable held : std_logic_vector(31 downto 0);
    variable held_last : std_logic;
    variable stalled : boolean := false;
  begin
    if rising_edge(clk) then
      if reset_n = '1' then
        cycle := cycle + 1;
        if stalls and cycle mod 401 < 300 then rx_ready <= '0'; else rx_ready <= '1'; end if;
        if stalled then
          assert rx_valid = '1' and rx = held and rx_last = held_last
            report "SPI FIFO AXI stall violation" severity failure;
        end if;
        stalled := rx_valid = '1' and rx_ready = '0';
        held := rx;
        held_last := rx_last;
        if rx_valid = '1' and rx_ready = '1' then
          for byte in 0 to 3 loop
            assert rx(byte * 8 + 7 downto byte * 8) =
              std_logic_vector(to_unsigned(((received * 4 + byte) * 17 + 3) mod 256, 8))
              report "SPI FIFO RX packing mismatch" severity failure;
          end loop;
          if (received + 1) mod 64 = 0 then
            assert rx_last = '1' report "Missing SPI packet boundary" severity failure;
          else
            assert rx_last = '0' report "Unexpected SPI packet boundary" severity failure;
          end if;
          received <= received + 1;
        end if;
      end if;
    end if;
  end process;
  process
    variable started : time;
  begin
    wait for 37 ns;
    reset_n <= '1';
    started := now;
    for byte in 0 to 511 loop
      wait until falling_edge(clk);
      tx <= std_logic_vector(to_unsigned(byte mod 256, 8));
      tx_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when tx_ready = '1';
      end loop;
      wait until falling_edge(clk);
      tx_valid <= '0';
      if byte = 255 then
        wait until received = 64;
        assert now - started <= 64 us
          report "FIFO SPI wrapper below 32 Mbit/s" severity failure;
        report "SPI FIFO wrapper 2048 bits in " & time'image(now - started);
        stalls <= true;
      end if;
    end loop;
    wait until received = 128;
    wait for 100 ns;
    assert transfers = 512 and ss_n = '1' and rx_valid = '0' severity failure;
    report "tb_spi_master_to_axis_fifo PASS";
    stop;
    wait;
  end process;
  process
  begin
    wait for 1 ms;
    assert false report "SPI FIFO watchdog expired" severity failure;
  end process;
end architecture;
