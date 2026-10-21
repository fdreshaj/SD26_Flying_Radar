library ieee;
use ieee.std_logic_1164.all;

entity ad9284_capture is
  generic (capture_pairs : positive := 1024);
  port (
    aclk, aresetn : in std_logic;
    trigger : in std_logic;
    ready, busy, done, capture_fault : out std_logic;
    sample_clk : in std_logic;
    sample_locked, sample_valid : in std_logic;
    sample_a, sample_b : in std_logic_vector(7 downto 0);
    m_axis_tdata : out std_logic_vector(31 downto 0);
    m_axis_tvalid, m_axis_tlast : out std_logic;
    m_axis_tready : in std_logic
  );
end entity;

architecture rtl of ad9284_capture is
  constant word_count : positive := capture_pairs / 2;
  type memory_t is array (0 to word_count - 1) of std_logic_vector(31 downto 0);
  signal memory : memory_t;
  attribute ram_style : string;
  attribute ram_style of memory : signal is "block";
  type state_t is (idle, acquiring, fetch, load, sending, faulted);
  signal state : state_t := idle;
  signal request, complete : std_logic := '0';
  signal request_sync, complete_sync, trigger_sync, locked_sync : std_logic_vector(1 downto 0) := "00";
  signal sample_reset, axis_reset : std_logic_vector(1 downto 0) := "00";
  signal trigger_previous, sample_active : std_logic := '0';
  signal seen_request : std_logic := '0';
  signal pair_index : natural range 0 to capture_pairs - 1 := 0;
  signal low_pair : std_logic_vector(15 downto 0) := (others => '0');
  signal read_address : natural range 0 to word_count - 1 := 0;
  signal read_data : std_logic_vector(31 downto 0);
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of request_sync, complete_sync, trigger_sync, locked_sync : signal is "TRUE";
  attribute ASYNC_REG of sample_reset, axis_reset : signal is "TRUE";
begin
  assert capture_pairs >= 2 and capture_pairs mod 2 = 0
    report "capture_pairs must be even and >= 2" severity failure;
  ready <= '1' when state = idle and locked_sync(1) = '1' and axis_reset(1) = '1' else '0';
  busy <= '0' when state = idle else '1';
  m_axis_tvalid <= '1' when state = sending else '0';
  m_axis_tlast <= '1' when state = sending and read_address = word_count - 1 else '0';

  process(sample_clk, aresetn)
  begin
    if aresetn = '0' then
      sample_reset <= "00";
    elsif rising_edge(sample_clk) then
      sample_reset <= sample_reset(0) & '1';
    end if;
  end process;
  process(aclk, aresetn)
  begin
    if aresetn = '0' then
      axis_reset <= "00";
    elsif rising_edge(aclk) then
      axis_reset <= axis_reset(0) & '1';
    end if;
  end process;

  process(sample_clk, aresetn)
  begin
    if aresetn = '0' then
      request_sync <= "00";
      sample_active <= '0';
      seen_request <= '0';
      complete <= '0';
      pair_index <= 0;
      low_pair <= (others => '0');
    elsif rising_edge(sample_clk) then
      if sample_reset(1) = '1' then
        request_sync <= request_sync(0) & request;
        if sample_active = '0' then
          if request_sync(1) /= seen_request then
            seen_request <= request_sync(1);
            pair_index <= 0;
            sample_active <= '1';
          end if;
        elsif sample_valid = '1' then
          if pair_index mod 2 = 0 then
            low_pair <= sample_b & sample_a;
          end if;
          if pair_index = capture_pairs - 1 then
            complete <= seen_request;
            sample_active <= '0';
          else
            pair_index <= pair_index + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- The request/complete handshake fences ownership of the entire RAM.
  -- No AXI read is published until all sample-domain writes have finished.
  process(sample_clk)
  begin
    if rising_edge(sample_clk) then
      if sample_reset(1) = '1' and sample_active = '1' and
         sample_valid = '1' and pair_index mod 2 = 1 then
        memory(pair_index / 2) <= sample_b & sample_a & low_pair;
      end if;
    end if;
  end process;
  process(aclk)
  begin
    if rising_edge(aclk) then
      read_data <= memory(read_address);
    end if;
  end process;

  process(aclk, aresetn)
  begin
    if aresetn = '0' then
      state <= idle;
      request <= '0';
      complete_sync <= "00";
      trigger_sync <= "00";
      locked_sync <= "00";
      trigger_previous <= '0';
      read_address <= 0;
      m_axis_tdata <= (others => '0');
      done <= '0';
      capture_fault <= '0';
    elsif rising_edge(aclk) then
      done <= '0';
      if axis_reset(1) = '1' then
        complete_sync <= complete_sync(0) & complete;
        trigger_sync <= trigger_sync(0) & trigger;
        locked_sync <= locked_sync(0) & sample_locked;
        trigger_previous <= trigger_sync(1);
        case state is
          when idle =>
            if trigger_sync(1) = '1' and trigger_previous = '0' and locked_sync(1) = '1' then
              request <= not request;
              state <= acquiring;
            end if;
          when acquiring =>
            if locked_sync(1) = '0' then
              capture_fault <= '1';
              state <= faulted;
            elsif complete_sync(1) = request then
              read_address <= 0;
              state <= fetch;
            end if;
          when fetch =>
            state <= load;
          when load =>
            m_axis_tdata <= read_data;
            state <= sending;
          when sending =>
            if m_axis_tready = '1' then
              if read_address = word_count - 1 then
                done <= '1';
                state <= idle;
              else
                read_address <= read_address + 1;
                state <= fetch;
              end if;
            end if;
          when faulted =>
            null;
        end case;
      end if;
    end if;
  end process;
end architecture;
