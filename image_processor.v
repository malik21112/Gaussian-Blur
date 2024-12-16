// Image Processing Module for Gaussian Blur
// Implements a real-time 3x3 Gaussian blur filter on a 160x120 RGB image
// Uses a finite state machine (FSM) design with double buffering
module image_processor (
    output reg [14:0] process_address,    // Memory address for current pixel
    output reg [23:0] processed_data,     // Processed pixel data (RGB)
    output reg write_enable,              // Memory write control signal
    output reg processing_done,           // Indicates processing completion
    output reg processing_active,         // Indicates active processing state
    input wire clk,                       // System clock
    input wire rst,                       // Reset signal
    input wire start_process,             // Trigger to start processing
    input wire [23:0] pixel_data,         // Input pixel data from memory
    input wire [14:0] display_address     // Current display memory address
);

// FSM states and control registers
reg [2:0] curr_state;                     // Current state of FSM
reg [7:0] x_pos;                          // Current X position in image
reg [7:0] y_pos;                          // Current Y position in image
reg [3:0] pixel_count;                    // Counter for pixel window loading
reg [23:0] window [8:0];                  // 3x3 window buffer for blur operation

// System parameters
parameter WIDTH = 160;                     // Image width
parameter HEIGHT = 120;                    // Image height

// FSM state definitions
parameter IDLE = 3'd0;                     // Waiting for start signal
parameter READ_PIXELS = 3'd1;              // Loading pixel window
parameter PROCESS = 3'd2;                  // Processing current window
parameter WRITE = 3'd3;                    // Writing result to memory

// Gaussian blur kernel parameters
// Implements the following 3x3 kernel:
// | 1 2 1 |
// | 2 4 2 | / 16
// | 1 2 1 |
parameter [3:0] CORNER_WEIGHT = 1;         // Weight for corner pixels
parameter [3:0] ADJACENT_WEIGHT = 2;       // Weight for adjacent pixels
parameter [3:0] CENTER_WEIGHT = 4;         // Weight for center pixel
parameter [3:0] TOTAL_WEIGHT = 16;         // Normalization factor (sum of weights)

// Function to calculate memory address from x,y coordinates
function [14:0] calc_address;
    input [7:0] x;
    input [7:0] y;
    begin
        calc_address = (y + (x * HEIGHT)); // Convert 2D coordinates to 1D address
    end
endfunction

// Main processing block
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        // Reset all control signals and registers
        processing_done <= 0;
        processing_active <= 0;
        write_enable <= 0;
        curr_state <= IDLE;
        x_pos <= 1;                        // Start at (1,1) to handle borders
        y_pos <= 1;
        pixel_count <= 0;
        process_address <= 0;
        processed_data <= 0;
    end else begin
        case (curr_state)
            // State for reading pixels into the 3x3 window
            READ_PIXELS: begin
                write_enable <= 0;
                
                // Calculate addresses for each position in 3x3 window
                case (pixel_count)
                    0: process_address <= calc_address(x_pos-1, y_pos-1); // Top-left
                    1: process_address <= calc_address(x_pos, y_pos-1);   // Top-center
                    2: process_address <= calc_address(x_pos+1, y_pos-1); // Top-right
                    3: process_address <= calc_address(x_pos-1, y_pos);   // Middle-left
                    4: process_address <= calc_address(x_pos, y_pos);     // Center
                    5: process_address <= calc_address(x_pos+1, y_pos);   // Middle-right
                    6: process_address <= calc_address(x_pos-1, y_pos+1); // Bottom-left
                    7: process_address <= calc_address(x_pos, y_pos+1);   // Bottom-center
                    8: process_address <= calc_address(x_pos+1, y_pos+1); // Bottom-right
                endcase

                // Store incoming pixel data in window buffer
                if (pixel_count > 0)
                    window[pixel_count-1] <= pixel_data;

                // When window is full, move to processing state
                if (pixel_count == 9) begin
                    window[8] <= pixel_data;
                    curr_state <= PROCESS;
                    pixel_count <= 0;
                end else
                    pixel_count <= pixel_count + 1;
            end

            // Idle state - waiting for start signal
            IDLE: begin
                if (start_process && !processing_done) begin
                    curr_state <= READ_PIXELS;
                    processing_active <= 1;
                    processing_done <= 0;
                    x_pos <= 1;
                    y_pos <= 1;
                    pixel_count <= 0;
                    write_enable <= 0;
                end else begin
                    processing_active <= 0;
                end
            end

            // Write state - store processed pixel and update position
            WRITE: begin
                write_enable <= 1;

                // Handle end of row and end of image conditions
                if (x_pos == WIDTH-2) begin
                    if (y_pos == HEIGHT-2) begin
                        curr_state <= IDLE;
                        processing_done <= 1;
                        processing_active <= 0;
                        write_enable <= 0;
                    end else begin
                        y_pos <= y_pos + 1;
                        x_pos <= 1;
                        curr_state <= READ_PIXELS;
                    end
                end else begin
                    x_pos <= x_pos + 1;
                    curr_state <= READ_PIXELS;
                end
            end

            // Process state - apply Gaussian blur to window
            PROCESS: begin
                reg [11:0] r_sum, g_sum, b_sum;  // 12-bit accumulators for each color

                // Process corner pixels (weight 1)
                r_sum = (window[0][23:16] + window[2][23:16] + 
                        window[6][23:16] + window[8][23:16]) * CORNER_WEIGHT;
                g_sum = (window[0][15:8] + window[2][15:8] + 
                        window[6][15:8] + window[8][15:8]) * CORNER_WEIGHT;
                b_sum = (window[0][7:0] + window[2][7:0] + 
                        window[6][7:0] + window[8][7:0]) * CORNER_WEIGHT;

                // Process center pixel (weight 4)
                r_sum = r_sum + window[4][23:16] * CENTER_WEIGHT;
                g_sum = g_sum + window[4][15:8] * CENTER_WEIGHT;
                b_sum = b_sum + window[4][7:0] * CENTER_WEIGHT;

                // Process adjacent pixels (weight 2)
                r_sum = r_sum + (window[1][23:16] + window[3][23:16] + 
                        window[5][23:16] + window[7][23:16]) * ADJACENT_WEIGHT;
                g_sum = g_sum + (window[1][15:8] + window[3][15:8] + 
                        window[5][15:8] + window[7][15:8]) * ADJACENT_WEIGHT;
                b_sum = b_sum + (window[1][7:0] + window[3][7:0] + 
                        window[5][7:0] + window[7][7:0]) * ADJACENT_WEIGHT;

                // Normalize by dividing by 16 (implemented as bit shift)
                processed_data <= {
                    r_sum[11:4],    // Upper 8 bits of each sum
                    g_sum[11:4],    // This effectively divides by 16
                    b_sum[11:4]
                };

                process_address <= calc_address(x_pos, y_pos);
                curr_state <= WRITE;
            end
        endcase
    end
end

endmodule