library ieee;
use ieee.std_logic_1164.all;

entity axis_byte_packetizer is
  generic (packet_bytes : positive := 256);
  port (
    aclk, aresetn : in std_logic;
    s_axis_tdata : in std_logic_vector(7 downto 0);
    s_axis_tvalid : in std_logic;
    s_axis_tready : out std_logic;
    m_axis_tdata : out std_logic_vector(31 downto 0);
    m_axis_tvalid, m_axis_tlast : out std_logic;
    m_axis_tready : in std_logic
  );
end entity;

architecture rtl of axis_byte_packetizer is
  signal partial : std_logic_vector(31 downto 0) := (others => '0');
  signal byte_index : natural range 0 to 3 := 0;
  signal packet_index : natural range 0 to packet_bytes - 1 := 0;
  signal valid, ready : std_logic := '0';
begin
  assert packet_bytes mod 4 = 0
    report "packet_bytes must be a multiple of four" severity failure;
  ready <= aresetn and (not valid or m_axis_tready);
  s_axis_tready <= ready;
  m_axis_tvalid <= valid;

  process(aclk, aresetn)
    variable assembled : std_logic_vector(31 downto 0);
  begin
    if aresetn = '0' then
      partial <= (others => '0');
      byte_index <= 0;
      packet_index <= 0;
      valid <= '0';
      m_axis_tdata <= (others => '0');
      m_axis_tlast <= '0';
    elsif rising_edge(aclk) then
      if valid = '1' and m_axis_tready = '1' then
        valid <= '0';
        m_axis_tlast <= '0';
      end if;
      if s_axis_tvalid = '1' and ready = '1' then
        assembled := partial;
        assembled(byte_index * 8 + 7 downto byte_index * 8) := s_axis_tdata;
        partial <= assembled;
        if byte_index = 3 then
          m_axis_tdata <= assembled;
          valid <= '1';
          byte_index <= 0;
          if packet_index = packet_bytes - 1 then
            m_axis_tlast <= '1';
          else
            m_axis_tlast <= '0';
          end if;
        else
          byte_index <= byte_index + 1;
        end if;
        if packet_index = packet_bytes - 1 then
          packet_index <= 0;
        else
          packet_index <= packet_index + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
