library ieee;
use ieee.std_logic_1164.all;

entity spi_slave is
  generic (
    data_length : positive := 8;
    cpol : std_logic := '0';
    cpha : std_logic := '0'
  );
  port (
    reset_n, sclk, ss_n, mosi : in std_logic;
    miso : out std_logic;
    tx_data : in std_logic_vector(data_length - 1 downto 0);
    tx_valid : in std_logic;
    tx_ready : out std_logic;
    rx_data : out std_logic_vector(data_length - 1 downto 0);
    rx_valid : out std_logic;
    rx_ready : in std_logic;
    word_clk : out std_logic;
    overflow, underrun : out std_logic
  );
end entity;

architecture rtl of spi_slave is
  signal sample_clk : std_logic;
  signal sample_count, shift_count : natural range 0 to data_length - 1 := 0;
  signal rx_shift, tx_latch : std_logic_vector(data_length - 1 downto 0);
  signal tx_selected : std_logic := '0';
  signal miso_reg : std_logic := '0';
begin
  -- Static inversion only: never gate a clock with chip select.
  sample_clk <= sclk when (cpol xor cpha) = '0' else not sclk;
  word_clk <= sample_clk;
  rx_data <= rx_shift(data_length - 2 downto 0) & mosi;
  rx_valid <= '1' when reset_n = '1' and ss_n = '0' and
                       sample_count = data_length - 1 else '0';
  tx_ready <= '1' when reset_n = '1' and ss_n = '0' and
                       sample_count = data_length - 1 and tx_selected = '1' else '0';

  process(sample_clk, reset_n, ss_n)
  begin
    if reset_n = '0' or ss_n = '1' then
      sample_count <= 0;
      rx_shift <= (others => '0');
    elsif rising_edge(sample_clk) then
      rx_shift <= rx_shift(data_length - 2 downto 0) & mosi;
      if sample_count = data_length - 1 then
        sample_count <= 0;
      else
        sample_count <= sample_count + 1;
      end if;
    end if;
  end process;

  process(sample_clk, reset_n)
  begin
    if reset_n = '0' then
      overflow <= '0';
      underrun <= '0';
    elsif rising_edge(sample_clk) then
      if ss_n = '0' then
        if sample_count = data_length - 1 and rx_ready = '0' then
          overflow <= '1';
        end if;
        if sample_count = 0 then
          if (cpha = '0' and tx_valid = '0') or
             (cpha = '1' and tx_selected = '0') then
            underrun <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  phase_zero : if cpha = '0' generate
    process(sample_clk, reset_n, ss_n)
    begin
      if reset_n = '0' or ss_n = '1' then
        tx_latch <= (others => '0');
        tx_selected <= '0';
      elsif rising_edge(sample_clk) then
        if sample_count = 0 then
          tx_selected <= tx_valid;
          if tx_valid = '1' then
            tx_latch <= tx_data;
          else
            tx_latch <= (others => '0');
          end if;
        end if;
      end if;
    end process;

    process(sample_clk, reset_n, ss_n)
    begin
      if reset_n = '0' or ss_n = '1' then
        shift_count <= 0;
      elsif falling_edge(sample_clk) then
        if shift_count = data_length - 1 then
          shift_count <= 0;
        else
          shift_count <= shift_count + 1;
        end if;
      end if;
    end process;

    miso <= 'Z' when ss_n = '1' or reset_n = '0' else
            tx_data(data_length - 1) when shift_count = 0 and tx_valid = '1' else
            '0' when shift_count = 0 else
            tx_latch(data_length - 1 - shift_count);
  end generate;

  phase_one : if cpha = '1' generate
    process(sample_clk, reset_n, ss_n)
    begin
      if reset_n = '0' or ss_n = '1' then
        shift_count <= 0;
        tx_latch <= (others => '0');
        tx_selected <= '0';
        miso_reg <= '0';
      elsif falling_edge(sample_clk) then
        if shift_count = 0 then
          tx_selected <= tx_valid;
          if tx_valid = '1' then
            tx_latch <= tx_data;
            miso_reg <= tx_data(data_length - 1);
          else
            tx_latch <= (others => '0');
            miso_reg <= '0';
          end if;
        else
          miso_reg <= tx_latch(data_length - 1 - shift_count);
        end if;
        if shift_count = data_length - 1 then
          shift_count <= 0;
        else
          shift_count <= shift_count + 1;
        end if;
      end if;
    end process;

    miso <= 'Z' when ss_n = '1' or reset_n = '0' else miso_reg;
  end generate;

  assert data_length >= 2 report "spi_slave requires data_length >= 2" severity failure;
end architecture;
