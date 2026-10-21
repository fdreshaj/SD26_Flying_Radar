library ieee;
use ieee.std_logic_1164.all;

entity spi_master is
  generic (
    data_length : positive := 8;
    clk_divider : positive := 1
  );
  port (
    clk, reset_n : in std_logic;
    enable, cpol, cpha : in std_logic;
    miso : in std_logic;
    sclk, ss_n, mosi, busy : out std_logic;
    tx : in std_logic_vector(data_length - 1 downto 0);
    rx : out std_logic_vector(data_length - 1 downto 0);
    done : out std_logic
  );
end entity;

architecture rtl of spi_master is
  type state_t is (idle, transfer, finish);
  signal state : state_t := idle;
  signal polarity, phase, serial_clk : std_logic := '0';
  signal tx_buffer, rx_buffer : std_logic_vector(data_length - 1 downto 0);
  signal divider : natural range 0 to clk_divider - 1 := 0;
  signal edge_count : natural range 0 to 2 * data_length - 1 := 0;
begin
  sclk <= serial_clk;

  process(clk, reset_n)
    variable leading, sample_edge : boolean;
  begin
    if reset_n = '0' then
      state <= idle;
      polarity <= '0';
      phase <= '0';
      serial_clk <= '0';
      ss_n <= '1';
      mosi <= '0';
      busy <= '0';
      done <= '0';
      rx <= (others => '0');
      tx_buffer <= (others => '0');
      rx_buffer <= (others => '0');
      divider <= 0;
      edge_count <= 0;
    elsif rising_edge(clk) then
      done <= '0';
      case state is
        when idle =>
          serial_clk <= cpol;
          ss_n <= '1';
          busy <= '0';
          if enable = '1' then
            polarity <= cpol;
            phase <= cpha;
            serial_clk <= cpol;
            tx_buffer <= tx;
            rx_buffer <= (others => '0');
            divider <= 0;
            edge_count <= 0;
            ss_n <= '0';
            busy <= '1';
            if cpha = '0' then
              mosi <= tx(data_length - 1);
            end if;
            state <= transfer;
          end if;
        when transfer =>
          if divider = clk_divider - 1 then
            divider <= 0;
            leading := edge_count mod 2 = 0;
            sample_edge := (leading and phase = '0') or
                           (not leading and phase = '1');
            serial_clk <= not serial_clk;
            if sample_edge then
              rx_buffer <= rx_buffer(data_length - 2 downto 0) & miso;
            elsif phase = '1' then
              mosi <= tx_buffer(data_length - 1);
              tx_buffer <= tx_buffer(data_length - 2 downto 0) & '0';
            else
              tx_buffer <= tx_buffer(data_length - 2 downto 0) & '0';
              mosi <= tx_buffer(data_length - 2);
            end if;
            if edge_count = 2 * data_length - 1 then
              state <= finish;
            else
              edge_count <= edge_count + 1;
            end if;
          else
            divider <= divider + 1;
          end if;
        when finish =>
          -- Retain chip select for a full half-period after the last edge.
          if divider = clk_divider - 1 then
            serial_clk <= polarity;
            ss_n <= '1';
            busy <= '0';
            done <= '1';
            rx <= rx_buffer;
            divider <= 0;
            state <= idle;
          else
            divider <= divider + 1;
          end if;
      end case;
    end if;
  end process;

  assert data_length >= 2 report "spi_master requires data_length >= 2" severity failure;
end architecture;
