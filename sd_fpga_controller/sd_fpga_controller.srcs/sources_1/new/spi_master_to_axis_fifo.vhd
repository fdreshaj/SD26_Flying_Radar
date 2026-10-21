library ieee;
use ieee.std_logic_1164.all;

entity spi_master_to_axis_fifo is
  generic (
    cpol : std_logic := '0';
    cpha : std_logic := '0';
    clk_divider : positive := 1;
    packet_bytes : positive := 256
  );
  port (
    aclk, aresetn : in std_logic;
    spi_sclk, spi_ss_n, spi_mosi : out std_logic;
    spi_miso : in std_logic;
    s_axis_tdata : in std_logic_vector(7 downto 0);
    s_axis_tvalid : in std_logic;
    s_axis_tready : out std_logic;
    m_axis_tdata : out std_logic_vector(31 downto 0);
    m_axis_tvalid, m_axis_tlast : out std_logic;
    m_axis_tready : in std_logic
  );
end entity;

architecture rtl of spi_master_to_axis_fifo is
  signal rx_data : std_logic_vector(7 downto 0);
  signal rx_valid, rx_ready : std_logic;
begin
  master : entity work.spi_master_to_axis
    generic map (cpol => cpol, cpha => cpha, clk_divider => clk_divider)
    port map (
      aclk => aclk, aresetn => aresetn,
      spi_sclk => spi_sclk, spi_ss_n => spi_ss_n,
      spi_mosi => spi_mosi, spi_miso => spi_miso,
      s_axis_tdata => s_axis_tdata, s_axis_tvalid => s_axis_tvalid,
      s_axis_tready => s_axis_tready,
      m_axis_tdata => rx_data, m_axis_tvalid => rx_valid, m_axis_tready => rx_ready
    );
  formatter : entity work.axis_byte_packetizer
    generic map (packet_bytes => packet_bytes)
    port map (
      aclk => aclk, aresetn => aresetn,
      s_axis_tdata => rx_data, s_axis_tvalid => rx_valid, s_axis_tready => rx_ready,
      m_axis_tdata => m_axis_tdata, m_axis_tvalid => m_axis_tvalid,
      m_axis_tlast => m_axis_tlast, m_axis_tready => m_axis_tready
    );
end architecture;
