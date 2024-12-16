module image_processing_system (
    output VGA_CLK,
    output VGA_HS,
    output VGA_VS,
    output [7:0] VGA_R,
    output [7:0] VGA_G,
    output [7:0] VGA_B,
    output VGA_BLANK_N,     
    output VGA_SYNC_N,
    input CLOCK_50,
    input [3:0] KEY
);

// Memory interface signals
wire [14:0] display_address;
wire [23:0] buffer_out;          // Changed from mem_data
wire [14:0] process_address;
wire [23:0] processed_data;
wire write_enable;
wire processing_done;
wire processing_active;

// VGA timing and coordinate signals
wire active_pixels;
wire frame_done;
wire [9:0] x_pos;               // Changed from x
wire [9:0] y_pos;               // Changed from y

// Core signals
wire main_clk;                  // Changed from clk
wire reset_n;                   // Changed from rst
assign main_clk = CLOCK_50;
assign reset_n = KEY[0];

// Memory arbitration
reg [1:0] buff_state;          // Changed from mem_state
wire proc_active;              // Changed from should_process
reg [14:0] current_address;
reg [23:0] current_data;

// Process control
reg key_prev;                  // Changed from prev_key3
reg filter_start;              // Changed from processing_triggered
reg [15:0] debounce_timer;     // Changed from debounce_counter
parameter DEBOUNCE_LIMIT = 16'd50000;

// Memory interface signals
wire [14:0] mem_address;
wire [23:0] pixel_out;         // Changed from output_data

assign proc_active = processing_active && !processing_done;
assign mem_address = proc_active ? process_address : display_address;
assign pixel_out = proc_active ? processed_data : buffer_out;

// Display address calculation
reg [14:0] calc_addr;          // Changed from calc_display_address
always @(*) begin
    if (x_pos < 640 && y_pos < 480) begin
        calc_addr = ((y_pos >> 2) + ((x_pos >> 2) * 120));
    end else begin
        calc_addr = 0;
    end
end
assign display_address = calc_addr;

// Memory state control
always @(posedge main_clk or negedge reset_n) begin
    if (!reset_n) begin
        buff_state <= 2'b00;
        current_address <= 0;
        current_data <= 0;
    end else begin
        if (proc_active) begin
            current_address <= process_address;
            current_data <= processed_data;
        end else begin
            current_address <= display_address;
            current_data <= buffer_out;
        end
    end
end

// Process control logic
always @(posedge main_clk or negedge reset_n) begin
    if (!reset_n) begin
        filter_start <= 0;
        key_prev <= 1'b1;
        debounce_timer <= 0;
    end else begin
        key_prev <= KEY[3];
        if (key_prev && !KEY[3] && (debounce_timer == 0)) begin
            filter_start <= 1;
            debounce_timer <= DEBOUNCE_LIMIT;
        end else if (filter_start && processing_done) begin
            filter_start <= 0;
        end
        if (debounce_timer > 0) 
            debounce_timer <= debounce_timer - 1;
    end
end

vga_frame_driver vga_driver (
    .clk(main_clk),
    .rst(reset_n),
    .x(x_pos),
    .y(y_pos),
    .active_pixels(active_pixels),
    .frame_done(frame_done),
    .VGA_BLANK_N(VGA_BLANK_N),
    .VGA_CLK(VGA_CLK),
    .VGA_HS(VGA_HS),
    .VGA_SYNC_N(VGA_SYNC_N),
    .VGA_VS(VGA_VS),
    .VGA_B(VGA_B),
    .VGA_G(VGA_G),
    .VGA_R(VGA_R),
    .the_vga_draw_frame_write_mem_address(display_address),
    .the_vga_draw_frame_write_mem_data(pixel_out),
    .the_vga_draw_frame_write_a_pixel(active_pixels && !proc_active)
);

vga_frame frame_mem (
    .clock(main_clk),
    .address(mem_address),
    .data(processed_data),
    .wren(write_enable && proc_active),
    .q(buffer_out)
);

image_processor processor (
    .clk(main_clk),
    .rst(reset_n),
    .start_process(filter_start),
    .pixel_data(buffer_out),
    .display_address(display_address),
    .process_address(process_address),
    .processed_data(processed_data),
    .write_enable(write_enable),
    .processing_done(processing_done),
    .processing_active(processing_active)
);

endmodule
