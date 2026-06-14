module top_tb;
    reg clk;
    reg reset;

    top uut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulacion.vcd"); // Nombre del archivo que va a generar
        $dumpvars(0, top_tb); // modulo top que contiene todos los estados del procesador

        clk = 0;
        reset = 1;
        
        #10;
        reset = 0;
        
         #300;
        $finish;
    end

endmodule

// nuestro testbench aplica un reset de 10 unidades de tiempo que limpia todos los 
// registros del pipeline y posiciona el program counter en cero, asegurando un inicio limpio. 
// Después, genera un ciclo de reloj continuo que actúa como el motor,
// empujando las instrucciones a través de las 5 etapas (Fetch a WriteBack) durante 30 ciclos completos 
// de ejecución. Durante todo este proceso, el testbench guarda el comportamiento de cada 
// registro interno del procesador mediante directivas $dumpvars, permitiendo analizar visualmente 
// la resolución de riesgos y el flujo de datos antes de finalizar la simulación.
