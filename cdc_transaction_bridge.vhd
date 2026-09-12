library ieee;
use ieee.std_logic_1164.all;

entity cdc_transaction_bridge is
    generic (
        FIFO_DEPTH : natural := 4
    );
    port (
        master_clk : in std_logic;
        dest_clk : in std_logic;
        rst : in std_logic;

        master_addr : in std_logic_vector(31 downto 0);
        master_write_data : in std_logic_vector(31 downto 0);
        master_rden : in std_logic;
        master_wren : in std_logic;
        master_ready : out std_logic;
        master_Q : out std_logic_vector(31 downto 0);

        dest_addr : out std_logic_vector(31 downto 0);
        dest_write_data : out std_logic_vector(31 downto 0);
        dest_rden : out std_logic;
        dest_wren : out std_logic;
        dest_ready : in std_logic;
        dest_Q : in std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of cdc_transaction_bridge is
    component dc_fifo
        generic (
            N : natural;
            REQUESTED_FIFO_DEPTH : natural
        );
        port (
            DATA_IN : in std_logic_vector(N-1 downto 0);
            WCLK : in std_logic;
            RCLK : in std_logic;
            RST : in std_logic;
            WREN : in std_logic;
            POP : in std_logic;
            FULL : buffer std_logic;
            EMPTY : buffer std_logic;
            OVF : out std_logic;
            DATA_OUT : out std_logic_vector(N-1 downto 0)
        );
    end component;

    -- Request format: [64] read flag, [63:32] address, [31:0] write data.
    constant REQUEST_WIDTH : natural := 65;

    signal request_fifo_data_in : std_logic_vector(REQUEST_WIDTH-1 downto 0);
    signal request_fifo_data_out : std_logic_vector(REQUEST_WIDTH-1 downto 0);
    signal request_fifo_wren : std_logic;
    signal request_fifo_pop : std_logic;
    signal request_fifo_full : std_logic;
    signal request_fifo_empty : std_logic;
    signal request_fifo_ovf : std_logic;

    signal response_fifo_data_out : std_logic_vector(31 downto 0);
    signal response_fifo_wren : std_logic;
    signal response_fifo_pop : std_logic;
    signal response_fifo_full : std_logic;
    signal response_fifo_empty : std_logic;
    signal response_fifo_ovf : std_logic;
    signal response_pop_pending : std_logic;
    signal response_capture_pending : std_logic;

    signal master_transaction_busy : std_logic;
    signal master_request_held : std_logic;
    signal master_waiting_read : std_logic;

    signal dest_transaction_busy : std_logic;
    signal dest_pop_pending : std_logic;
    signal dest_capture_pending : std_logic;
    signal dest_request_is_read : std_logic;
    signal dest_request_addr : std_logic_vector(31 downto 0);
    signal dest_request_data : std_logic_vector(31 downto 0);

begin
    -- Accept one request at a time from the master. master_request_held
    -- prevents re-enqueueing while the master keeps its enable asserted.
    request_fifo_data_in <= master_rden & master_addr & master_write_data;
    request_fifo_wren <= '1' when master_transaction_busy = '0' and
                                  master_request_held = '0' and
                                  (master_rden = '1' or master_wren = '1') and
                                  request_fifo_full = '0' else '0';

    -- The FIFO uses the legacy read convention: POP is asserted first and
    -- DATA_OUT is captured on the following destination-clock cycle.
    request_fifo_pop <= dest_pop_pending;

    -- A read response is written only after the destination reports valid
    -- data. Writes complete when their request is accepted by the FIFO.
    response_fifo_wren <= '1' when dest_transaction_busy = '1' and
                                   dest_request_is_read = '1' and
                                   dest_ready = '1' and
                                   response_fifo_full = '0' else '0';

    -- The response FIFO follows the same legacy POP -> DATA_OUT timing as
    -- the request FIFO, so capture is split into two master-clock cycles.
    response_fifo_pop <= response_pop_pending;

    -- Request path: master clock to destination clock.
    request_fifo : dc_fifo
        generic map (
            N => REQUEST_WIDTH,
            REQUESTED_FIFO_DEPTH => FIFO_DEPTH
        )
        port map (
            DATA_IN => request_fifo_data_in,
            WCLK => master_clk,
            RCLK => dest_clk,
            RST => rst,
            WREN => request_fifo_wren,
            POP => request_fifo_pop,
            FULL => request_fifo_full,
            EMPTY => request_fifo_empty,
            OVF => request_fifo_ovf,
            DATA_OUT => request_fifo_data_out
        );

    -- Response path: destination clock back to master clock.
    response_fifo : dc_fifo
        generic map (
            N => 32,
            REQUESTED_FIFO_DEPTH => FIFO_DEPTH
        )
        port map (
            DATA_IN => dest_Q,
            WCLK => dest_clk,
            RCLK => master_clk,
            RST => rst,
            WREN => response_fifo_wren,
            POP => response_fifo_pop,
            FULL => response_fifo_full,
            EMPTY => response_fifo_empty,
            OVF => response_fifo_ovf,
            DATA_OUT => response_fifo_data_out
        );

    master_proc : process(master_clk, rst)
    begin
        if rst = '1' then
            master_transaction_busy <= '0';
            master_request_held <= '0';
            master_waiting_read <= '0';
            response_pop_pending <= '0';
            response_capture_pending <= '0';
            master_ready <= '0';
            master_Q <= (others => '0');
        elsif rising_edge(master_clk) then
            master_ready <= '0';

            -- A pending read keeps the master blocked until its response is
            -- removed from the response FIFO.
            if master_rden = '0' and master_wren = '0' then
                master_request_held <= '0';
                if master_waiting_read = '0' then
                    master_transaction_busy <= '0';
                end if;
            elsif master_request_held = '0' and request_fifo_wren = '1' then
                master_request_held <= '1';
                master_transaction_busy <= '1';
                master_waiting_read <= master_rden;
                if master_wren = '1' then
                    master_ready <= '1';
                end if;
            end if;

            if response_capture_pending = '1' then
                -- For reads, ready means that the returned data is valid.
                master_Q <= response_fifo_data_out;
                master_ready <= '1';
                master_waiting_read <= '0';
                master_transaction_busy <= '0';
                response_capture_pending <= '0';
            elsif response_pop_pending = '1' then
                response_pop_pending <= '0';
                response_capture_pending <= '1';
            elsif master_waiting_read = '1' and response_fifo_empty = '0' then
                response_pop_pending <= '1';
            end if;
        end if;
    end process;

    dest_proc : process(dest_clk, rst)
    begin
        if rst = '1' then
            dest_transaction_busy <= '0';
            dest_pop_pending <= '0';
            dest_capture_pending <= '0';
            dest_request_is_read <= '0';
            dest_request_addr <= (others => '0');
            dest_request_data <= (others => '0');
        elsif rising_edge(dest_clk) then
            -- Separate POP from capture because DATA_OUT follows the legacy
            -- FIFO pointer convention and becomes valid one cycle later.
            if dest_capture_pending = '1' then
                dest_transaction_busy <= '1';
                dest_request_is_read <= request_fifo_data_out(64);
                dest_request_addr <= request_fifo_data_out(63 downto 32);
                dest_request_data <= request_fifo_data_out(31 downto 0);
                dest_capture_pending <= '0';
            elsif dest_pop_pending = '1' then
                dest_pop_pending <= '0';
                dest_capture_pending <= '1';
            elsif dest_transaction_busy = '0' and request_fifo_empty = '0' then
                dest_pop_pending <= '1';
            elsif dest_transaction_busy = '1' then
                -- Writes finish after presentation to the destination.
                -- Reads stay active until their response is enqueued.
                if dest_request_is_read = '0' then
                    dest_transaction_busy <= '0';
                elsif dest_ready = '1' and response_fifo_full = '0' then
                    dest_transaction_busy <= '0';
                end if;
            end if;
        end if;
    end process;

    dest_addr <= dest_request_addr;
    dest_write_data <= dest_request_data;
    -- Keep the destination request stable while the peripheral processes it.
    dest_rden <= dest_transaction_busy and dest_request_is_read;
    dest_wren <= dest_transaction_busy and not dest_request_is_read;
end architecture;
