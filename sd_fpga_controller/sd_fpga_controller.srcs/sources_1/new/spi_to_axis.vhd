library ieee;
use ieee.std_logic_1164.all;

entity spi_to_axis is
  generic (
    cpol : std_logic := '0';
    cpha : std_logic := '0';
    fifo_address_bits : positive := 6
  );
  port (
    aclk, aresetn : in std_logic;
    spi_sclk, spi_ss_n, spi_mosi : in std_logic;
    spi_miso : out std_logic;
    m_axis_tdata : out std_logic_vector(7 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in std_logic;
    s_axis_tdata : in std_logic_vector(7 downto 0);
    s_axis_tvalid : in std_logic;
    s_axis_tready : out std_logic;
    rx_overflow, tx_underrun : out std_logic
  );
end entity;

architecture rtl of spi_to_axis is
  signal word_clk, rx_valid, rx_ready, tx_valid, tx_ready : std_logic;
  signal rx_data, tx_data : std_logic_vector(7 downto 0);
  signal overflow_spi, underrun_spi : std_logic;
  signal overflow_sync, underrun_sync : std_logic_vector(1 downto 0) := "00";
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of overflow_sync, underrun_sync : signal is "TRUE";
begin
  rx_overflow <= overflow_sync(1);
  tx_underrun <= underrun_sync(1);
  serial_port : entity work.spi_slave
    generic map (data_length => 8, cpol => cpol, cpha => cpha)
    port map (
      reset_n => aresetn, sclk => spi_sclk, ss_n => spi_ss_n, mosi => spi_mosi,
      miso => spi_miso, tx_data => tx_data, tx_valid => tx_valid,
      tx_ready => tx_ready, rx_data => rx_data, rx_valid => rx_valid,
      rx_ready => rx_ready, word_clk => word_clk,
      overflow => overflow_spi, underrun => underrun_spi
    );

  rx_fifo : entity work.spi_async_fifo
    generic map (data_width => 8, address_bits => fifo_address_bits)
    port map (
      reset_n => aresetn,
      wr_clk => word_clk, wr_data => rx_data, wr_valid => rx_valid, wr_ready => rx_ready,
      rd_clk => aclk, rd_data => m_axis_tdata, rd_valid => m_axis_tvalid,
      rd_ready => m_axis_tready
    );

  tx_fifo : entity work.spi_async_fifo
    generic map (data_width => 8, address_bits => fifo_address_bits)
    port map (
      reset_n => aresetn,
      wr_clk => aclk, wr_data => s_axis_tdata, wr_valid => s_axis_tvalid,
      wr_ready => s_axis_tready,
      rd_clk => word_clk, rd_data => tx_data, rd_valid => tx_valid, rd_ready => tx_ready
    );

  process(aclk, aresetn)
  begin
    if aresetn = '0' then
      overflow_sync <= "00";
      underrun_sync <= "00";
    elsif rising_edge(aclk) then
      overflow_sync <= overflow_sync(0) & overflow_spi;
      underrun_sync <= underrun_sync(0) & underrun_spi;
    end if;
  end process;
end architecture;
