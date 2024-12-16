module image_processor (
    output reg [14:0] process_address,
    output reg [23:0] processed_data,
    output reg write_enable,
    output reg processing_done,
    output reg processing_active,
    input wire clk,
    input wire rst,
    input wire start_process,
    input wire [23:0] pixel_data,
    input wire [14:0] display_address
);

// FSM states and registers
reg [2:0] curr_state;
reg [7:0] x_pos;
reg [7:0] y_pos;
reg [3:0] pixel_count;
reg [23:0] window [8:0];

// Parameters
parameter WIDTH = 160;
parameter HEIGHT = 120;
parameter IDLE = 3'd0;
parameter READ_PIXELS = 3'd1;
parameter PROCESS = 3'd2;
parameter WRITE = 3'd3;

// Gaussian blur parameters
parameter [3:0] CORNER_WEIGHT = 1;
parameter [3:0] ADJACENT_WEIGHT = 2;
parameter [3:0] CENTER_WEIGHT = 4;
parameter [4:0] TOTAL_WEIGHT = 16;

function [14:0] calc_address;
    input [7:0] x;
    input [7:0] y;
    begin
        calc_address = (y + (x * HEIGHT));
    end
endfunction

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        processing_done <= 0;
        processing_active <= 0;
        write_enable <= 0;
        curr_state <= IDLE;
        x_pos <= 1;
        y_pos <= 1;
        pixel_count <= 0;
        process_address <= 0;
        processed_data <= 0;
    end else begin
        case (curr_state)
            READ_PIXELS: begin
                write_enable <= 0;
                
                case (pixel_count)
                    0: process_address <= calc_address(x_pos-1, y_pos-1);
                    1: process_address <= calc_address(x_pos, y_pos-1);
                    2: process_address <= calc_address(x_pos+1, y_pos-1);
                    3: process_address <= calc_address(x_pos-1, y_pos);
                    4: process_address <= calc_address(x_pos, y_pos);
                    5: process_address <= calc_address(x_pos+1, y_pos);
                    6: process_address <= calc_address(x_pos-1, y_pos+1);
                    7: process_address <= calc_address(x_pos, y_pos+1);
                    8: process_address <= calc_address(x_pos+1, y_pos+1);
                endcase

                if (pixel_count > 0)
                    window[pixel_count-1] <= pixel_data;

                if (pixel_count == 9) begin
                    window[8] <= pixel_data;
                    curr_state <= PROCESS;
                    pixel_count <= 0;
                end else
                    pixel_count <= pixel_count + 1;
            end

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

            WRITE: begin
                write_enable <= 1;

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

            PROCESS: begin
                reg [11:0] r_sum, g_sum, b_sum;

                // Corner pixels
                r_sum = (window[0][23:16] + window[2][23:16] + 
                        window[6][23:16] + window[8][23:16]) * CORNER_WEIGHT;
                g_sum = (window[0][15:8] + window[2][15:8] + 
                        window[6][15:8] + window[8][15:8]) * CORNER_WEIGHT;
                b_sum = (window[0][7:0] + window[2][7:0] + 
                        window[6][7:0] + window[8][7:0]) * CORNER_WEIGHT;

                // Center pixel
                r_sum = r_sum + window[4][23:16] * CENTER_WEIGHT;
                g_sum = g_sum + window[4][15:8] * CENTER_WEIGHT;
                b_sum = b_sum + window[4][7:0] * CENTER_WEIGHT;

                // Adjacent pixels
                r_sum = r_sum + (window[1][23:16] + window[3][23:16] + 
                        window[5][23:16] + window[7][23:16]) * ADJACENT_WEIGHT;
                g_sum = g_sum + (window[1][15:8] + window[3][15:8] + 
                        window[5][15:8] + window[7][15:8]) * ADJACENT_WEIGHT;
                b_sum = b_sum + (window[1][7:0] + window[3][7:0] + 
                        window[5][7:0] + window[7][7:0]) * ADJACENT_WEIGHT;

                processed_data <= {
                    r_sum[11:4],
                    g_sum[11:4],
                    b_sum[11:4]
                };

                process_address <= calc_address(x_pos, y_pos);
                curr_state <= WRITE;
            end
        endcase
    end
end

endmodule