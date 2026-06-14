module top_tb;
    reg clk;
    reg reset;

    top uut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulacion.vcd"); // Nombre del archivo que va a generar
        $dumpvars(0, top_tb);

        clk = 0;
        reset = 1;
        
        #10;
        reset = 0;
        
         #300;
        $finish;
    end

endmodule
