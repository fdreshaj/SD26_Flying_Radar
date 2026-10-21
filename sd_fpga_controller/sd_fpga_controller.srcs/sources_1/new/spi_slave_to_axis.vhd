library ieee;
use ieee.std_logic_1164.all;

entity spi_slave_to_axis is
  generic (
    cpol : std_logic := '0';
    cpha : std_logic := '0';
    fifo_address_bits : positive := 6
  );
  port (
    aclk, aresetn : in std_logic;
    spi_sclk, spi_ss_n, spi_mosi : in std_logic;
    spi_miso : out std_logic;
    s_axis_tdata : in std_logic_vector(7 downto 0);
    s_axis_tvalid : in std_logic;
    s_axis_tready : out std_logic;
    m_axis_tdata : out std_logic_vector(7 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in std_logic;
    rx_overflow, tx_underrun : out std_logic
  );
end entity;

architecture rtl of spi_slave_to_axis is
begin
  bridge : entity work.spi_to_axis
    generic map (cpol => cpol, cpha => cpha, fifo_address_bits => fifo_address_bits)
    port map (
      aclk => aclk, aresetn => aresetn,
      spi_sclk => spi_sclk, spi_ss_n => spi_ss_n,
      spi_mosi => spi_mosi, spi_miso => spi_miso,
      s_axis_tdata => s_axis_tdata, s_axis_tvalid => s_axis_tvalid,
      s_axis_tready => s_axis_tready,
      m_axis_tdata => m_axis_tdata, m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      rx_overflow => rx_overflow, tx_underrun => tx_underrun
    );
end architecture;
