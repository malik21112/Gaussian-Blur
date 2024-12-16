module vga_frame_driver(
    input clk,
    input rst,
    output active_pixels,
    output frame_done,
    output [9:0] x,
    output [9:0] y,
    output VGA_BLANK_N,
    output VGA_CLK,
    output VGA_HS,
    output [7:0] VGA_B,
    output [7:0] VGA_G,
    output [7:0] VGA_R,
    output VGA_SYNC_N,
    output VGA_VS,
    input [14:0] the_vga_draw_frame_write_mem_address,
    input [23:0] the_vga_draw_frame_write_mem_data,
    input the_vga_draw_frame_write_a_pixel
);

// Parameters
parameter MEMORY_SIZE = 16'd19200; // 160*120
parameter VIRTUAL_PIXEL_WIDTH = 16'd160;
parameter VIRTUAL_PIXEL_HEIGHT = 16'd120;

// Buffer control signals
reg [1:0] buffer_state;
reg buffer_swap_pending;
reg current_read_buffer;

// Memory control signals
reg [14:0] mem0_address;
reg [14:0] mem1_address;
reg [23:0] mem0_data;
reg [23:0] mem1_data;
reg mem0_wren;
reg mem1_wren;
wire [23:0] mem0_q;
wire [23:0] mem1_q;

// Calculate pixel address
wire [14:0] pixel_address = (y[8:2]) + ((x[9:2]) * VIRTUAL_PIXEL_HEIGHT);

// Instantiate two RAM blocks using vga_frame module
vga_frame buffer0 (
    .address(mem0_address),
    .clock(clk),
    .data(mem0_data),
    .wren(mem0_wren),
    .q(mem0_q)
);

vga_frame buffer1 (
    .address(mem1_address),
    .clock(clk),
    .data(mem1_data),
    .wren(mem1_wren),
    .q(mem1_q)
);

// VGA timing controller
vga_driver vga_timing(
    .clk(clk),
    .rst(rst),
    .vga_clk(VGA_CLK),
    .hsync(VGA_HS),
    .vsync(VGA_VS),
    .active_pixels(active_pixels),
    .frame_done(frame_done),
    .xPixel(x),
    .yPixel(y),
    .VGA_BLANK_N(VGA_BLANK_N),
    .VGA_SYNC_N(VGA_SYNC_N)
);

// Unified memory control block
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        buffer_state <= 2'b00;
        current_read_buffer <= 0;
        buffer_swap_pending <= 0;
        mem0_wren <= 0;
        mem1_wren <= 0;
        mem0_address <= 0;
        mem1_address <= 0;
        mem0_data <= 0;
        mem1_data <= 0;
    end else begin
        // Default assignments
        mem0_wren <= 0;
        mem1_wren <= 0;
        
        // Set read addresses by default
        if (current_read_buffer == 0) begin
            mem0_address <= pixel_address;
            mem1_address <= the_vga_draw_frame_write_mem_address;
        end else begin
            mem1_address <= pixel_address;
            mem0_address <= the_vga_draw_frame_write_mem_address;
        end

        // Handle write operations
        if (the_vga_draw_frame_write_a_pixel) begin
            if (current_read_buffer == 0) begin
                mem1_data <= the_vga_draw_frame_write_mem_data;
                mem1_wren <= 1;
            end else begin
                mem0_data <= the_vga_draw_frame_write_mem_data;
                mem0_wren <= 1;
            end
            buffer_swap_pending <= 1;
        end

        // Handle buffer swapping
        if (frame_done && buffer_swap_pending) begin
            current_read_buffer <= ~current_read_buffer;
            buffer_swap_pending <= 0;
        end
    end
end

// Output RGB data
reg [23:0] output_pixel;
always @(*) begin
    if (active_pixels) begin
        output_pixel = current_read_buffer ? mem1_q : mem0_q;
    end else begin
        output_pixel = 24'h000000;
    end
end

assign VGA_R = output_pixel[23:16];
assign VGA_G = output_pixel[15:8];
assign VGA_B = output_pixel[7:0];

endmodule