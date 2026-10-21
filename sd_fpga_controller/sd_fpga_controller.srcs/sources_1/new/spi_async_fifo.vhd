library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_async_fifo is
  generic (
    data_width : positive := 8;
    address_bits : positive := 4
  );
  port (
    reset_n : in std_logic;
    wr_clk : in std_logic;
    wr_data : in std_logic_vector(data_width - 1 downto 0);
    wr_valid : in std_logic;
    wr_ready : out std_logic;
    rd_clk : in std_logic;
    rd_data : out std_logic_vector(data_width - 1 downto 0);
    rd_valid : out std_logic;
    rd_ready : in std_logic
  );
end entity;

architecture rtl of spi_async_fifo is
  subtype pointer_t is unsigned(address_bits downto 0);
  type memory_t is array(0 to 2 ** address_bits - 1) of
    std_logic_vector(data_width - 1 downto 0);
  signal memory : memory_t;
  signal wr_binary, rd_binary, wr_gray, rd_gray : pointer_t := (others => '0');
  signal rd_gray_meta, rd_gray_sync, wr_gray_meta, wr_gray_sync : pointer_t := (others => '0');
  signal wr_reset, rd_reset : std_logic_vector(1 downto 0) := "00";
  signal full, empty : std_logic;
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rd_gray_meta, rd_gray_sync, wr_gray_meta, wr_gray_sync : signal is "TRUE";
  attribute ASYNC_REG of wr_reset, rd_reset : signal is "TRUE";
begin
  assert address_bits >= 2 report "FIFO address_bits must be >= 2" severity failure;
  full <= '1' when wr_gray =
    ((not rd_gray_sync(address_bits downto address_bits - 1)) &
      rd_gray_sync(address_bits - 2 downto 0)) else '0';
  empty <= '1' when rd_gray = wr_gray_sync else '0';
  wr_ready <= not full and wr_reset(1);
  rd_valid <= not empty and rd_reset(1);
  -- First-word fall-through, intended for distributed RAM on the Artix-7.
  rd_data <= memory(to_integer(rd_binary(address_bits - 1 downto 0)));

  process(wr_clk, reset_n)
  begin
    if reset_n = '0' then
      wr_reset <= "00";
    elsif rising_edge(wr_clk) then
      wr_reset <= wr_reset(0) & '1';
    end if;
  end process;

  process(rd_clk, reset_n)
  begin
    if reset_n = '0' then
      rd_reset <= "00";
    elsif rising_edge(rd_clk) then
      rd_reset <= rd_reset(0) & '1';
    end if;
  end process;

  process(wr_clk, reset_n)
    variable next_pointer : pointer_t;
  begin
    if reset_n = '0' then
      wr_binary <= (others => '0');
      wr_gray <= (others => '0');
      rd_gray_meta <= (others => '0');
      rd_gray_sync <= (others => '0');
    elsif rising_edge(wr_clk) then
      if wr_reset(1) = '0' then
        wr_binary <= (others => '0');
        wr_gray <= (others => '0');
        rd_gray_meta <= (others => '0');
        rd_gray_sync <= (others => '0');
      else
        rd_gray_meta <= rd_gray;
        rd_gray_sync <= rd_gray_meta;
        if wr_valid = '1' and full = '0' then
          next_pointer := wr_binary + 1;
          wr_binary <= next_pointer;
          wr_gray <= next_pointer xor shift_right(next_pointer, 1);
        end if;
      end if;
    end if;
  end process;

  process(wr_clk)
  begin
    if rising_edge(wr_clk) then
      if wr_reset(1) = '1' and wr_valid = '1' and full = '0' then
        memory(to_integer(wr_binary(address_bits - 1 downto 0))) <= wr_data;
      end if;
    end if;
  end process;

  process(rd_clk, reset_n)
    variable next_pointer : pointer_t;
  begin
    if reset_n = '0' then
      rd_binary <= (others => '0');
      rd_gray <= (others => '0');
      wr_gray_meta <= (others => '0');
      wr_gray_sync <= (others => '0');
    elsif rising_edge(rd_clk) then
      if rd_reset(1) = '0' then
        rd_binary <= (others => '0');
        rd_gray <= (others => '0');
        wr_gray_meta <= (others => '0');
        wr_gray_sync <= (others => '0');
      else
        wr_gray_meta <= wr_gray;
        wr_gray_sync <= wr_gray_meta;
        if rd_ready = '1' and empty = '0' then
          next_pointer := rd_binary + 1;
          rd_binary <= next_pointer;
          rd_gray <= next_pointer xor shift_right(next_pointer, 1);
        end if;
      end if;
    end if;
  end process;
end architecture;
