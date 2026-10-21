library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_axis_byte_packetizer is
  generic (packet_bytes : positive := 256);
end entity;

architecture test of tb_axis_byte_packetizer is
  signal clk : std_logic := '0';
  signal reset_n, tx_valid, tx_ready, rx_valid, rx_last, rx_ready : std_logic := '0';
  signal tx : std_logic_vector(7 downto 0);
  signal rx : std_logic_vector(31 downto 0);
  signal received : natural := 0;
begin
  clk <= not clk after 5 ns;
  dut : entity work.axis_byte_packetizer
    generic map (packet_bytes => packet_bytes)
    port map (
      aclk => clk, aresetn => reset_n,
      s_axis_tdata => tx, s_axis_tvalid => tx_valid, s_axis_tready => tx_ready,
      m_axis_tdata => rx, m_axis_tvalid => rx_valid,
      m_axis_tlast => rx_last, m_axis_tready => rx_ready
    );
  process(clk)
    variable cycle : natural := 0;
    variable held : std_logic_vector(31 downto 0);
    variable held_last : std_logic;
    variable stalled : boolean := false;
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        received <= 0;
        rx_ready <= '0';
        stalled := false;
      else
        cycle := cycle + 1;
        if cycle mod 29 < 19 then rx_ready <= '0'; else rx_ready <= '1'; end if;
        if stalled then
          assert rx_valid = '1' and rx = held and rx_last = held_last severity failure;
        end if;
        stalled := rx_valid = '1' and rx_ready = '0';
        held := rx;
        held_last := rx_last;
        if rx_valid = '1' and rx_ready = '1' then
          for byte in 0 to 3 loop
            assert rx(byte * 8 + 7 downto byte * 8) =
              std_logic_vector(to_unsigned((received * 4 + byte) mod 256, 8))
              report "Packetizer byte order mismatch" severity failure;
          end loop;
          if (received + 1) mod (packet_bytes / 4) = 0 then
            assert rx_last = '1' report "Missing packetizer TLAST" severity failure;
          else
            assert rx_last = '0' report "Early packetizer TLAST" severity failure;
          end if;
          received <= received + 1;
        end if;
      end if;
    end if;
  end process;
  process
    procedure send(value : natural) is
    begin
      wait until falling_edge(clk);
      tx <= std_logic_vector(to_unsigned(value mod 256, 8));
      tx_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when tx_ready = '1';
      end loop;
      wait until falling_edge(clk);
      tx_valid <= '0';
    end procedure;
  begin
    wait for 37 ns;
    reset_n <= '1';
    -- Discard an incomplete word on reset.
    send(99);
    send(98);
    reset_n <= '0';
    wait for 23 ns;
    reset_n <= '1';
    for byte in 0 to packet_bytes * 3 - 1 loop send(byte); end loop;
    wait until received = packet_bytes * 3 / 4;
    wait for 50 ns;
    assert rx_valid = '0' severity failure;
    report "tb_axis_byte_packetizer PASS";
    stop;
    wait;
  end process;
  process
  begin
    wait for 1 ms;
    assert false report "Packetizer watchdog expired" severity failure;
  end process;
end architecture;
