library ieee;
use ieee.std_logic_1164.all;

entity spi_master_to_axis is
  generic (
    cpol : std_logic := '0';
    cpha : std_logic := '0';
    clk_divider : positive := 1
  );
  port (
    aclk, aresetn : in std_logic;
    spi_sclk, spi_ss_n, spi_mosi : out std_logic;
    spi_miso : in std_logic;
    s_axis_tdata : in std_logic_vector(7 downto 0);
    s_axis_tvalid : in std_logic;
    s_axis_tready : out std_logic;
    m_axis_tdata : out std_logic_vector(7 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in std_logic
  );
end entity;

architecture rtl of spi_master_to_axis is
  signal active, result_valid : std_logic := '0';
  signal ready, start, done : std_logic;
  signal received : std_logic_vector(7 downto 0);
begin
  -- Reserve the result slot before starting: SPI cannot stall mid-word.
  ready <= aresetn and not active and (not result_valid or m_axis_tready);
  s_axis_tready <= ready;
  start <= ready and s_axis_tvalid;
  m_axis_tvalid <= result_valid;

  serial_port : entity work.spi_master
    generic map (data_length => 8, clk_divider => clk_divider)
    port map (
      clk => aclk, reset_n => aresetn, enable => start, cpol => cpol, cpha => cpha,
      miso => spi_miso, sclk => spi_sclk, ss_n => spi_ss_n, mosi => spi_mosi,
      busy => open, tx => s_axis_tdata, rx => received, done => done
    );

  process(aclk, aresetn)
  begin
    if aresetn = '0' then
      active <= '0';
      result_valid <= '0';
      m_axis_tdata <= (others => '0');
    elsif rising_edge(aclk) then
      if result_valid = '1' and m_axis_tready = '1' then
        result_valid <= '0';
      end if;
      if start = '1' then
        active <= '1';
      end if;
      if active = '1' and done = '1' then
        active <= '0';
        m_axis_tdata <= received;
        result_valid <= '1';
      end if;
    end if;
  end process;
end architecture;
