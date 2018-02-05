/////////////////////////////////////////////////////////////////
//                                                             //
//    ██████╗  ██████╗  █████╗                                 //
//    ██╔══██╗██╔═══██╗██╔══██╗                                //
//    ██████╔╝██║   ██║███████║                                //
//    ██╔══██╗██║   ██║██╔══██║                                //
//    ██║  ██║╚██████╔╝██║  ██║                                //
//    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝                                //
//          ██╗      ██████╗  ██████╗ ██╗ ██████╗              //
//          ██║     ██╔═══██╗██╔════╝ ██║██╔════╝              //
//          ██║     ██║   ██║██║  ███╗██║██║                   //
//          ██║     ██║   ██║██║   ██║██║██║                   //
//          ███████╗╚██████╔╝╚██████╔╝██║╚██████╗              //
//          ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝              //
//                                                             //
//    RISC-V                                                   //
//    AHB Memory Model                                         //
//                                                             //
/////////////////////////////////////////////////////////////////
//                                                             //
//     Copyright (C) 2014-2015 ROA Logic BV                    //
//                                                             //
//    This confidential and proprietary software is provided   //
//  under license. It may only be used as authorised by a      //
//  licensing agreement from ROA Logic BV.                     //
//  No parts may be copied, reproduced, distributed, modified  //
//  or adapted in any form without prior written consent.      //
//  This entire notice must be reproduced on all authorised    //
//  copies.                                                    //
//                                                             //
//    TO THE MAXIMUM EXTENT PERMITTED BY LAW, IN NO EVENT      //
//  SHALL ROA LOGIC BE LIABLE FOR ANY INDIRECT, SPECIAL,       //
//  CONSEQUENTIAL OR INCIDENTAL DAMAGES WHATSOEVER (INCLUDING, //
//  BUT NOT LIMITED TO, DAMAGES FOR LOSS OF PROFIT, BUSINESS   //
//  INTERRUPTIONS OR LOSS OF INFORMATION) ARISING OUT OF THE   //
//  USE OR INABILITY TO USE THE PRODUCT WHETHER BASED ON A     //
//  CLAIM UNDER CONTRACT, TORT OR OTHER LEGAL THEORY, EVEN IF  //
//  ROA LOGIC WAS ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.  //
//  IN NO EVENT WILL ROA LOGIC BE LIABLE TO ANY AGGREGATED     //
//  CLAIMS MADE AGAINST ROA LOGIC GREATER THAN THE FEES PAID   //
//  FOR THE PRODUCT                                            //
//                                                             //
/////////////////////////////////////////////////////////////////

// Change History:
//   2017-02-22: Added BASE parameter
//

module memory_model_ahb3lite #(
  parameter ADDR_WIDTH = 16,
  parameter DATA_WIDTH = 32,

  parameter BASE       = 'h0,  //offset where to load program

  parameter PORTS      = 2,
  parameter LATENCY    = 1,
  parameter BURST      = 8
)
(
  input                          HCLK,
  input                          HRESETn,

  input      [              1:0] HTRANS [PORTS],
  output                         HREADY [PORTS],
  output                         HRESP  [PORTS],

  input      [ADDR_WIDTH   -1:0] HADDR  [PORTS],
  input                          HWRITE [PORTS],
  input      [              2:0] HSIZE  [PORTS],
  input      [              3:0] HBURST [PORTS],
  input      [DATA_WIDTH   -1:0] HWDATA [PORTS],
  output reg [DATA_WIDTH   -1:0] HRDATA [PORTS]
);
  ////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  import ahb3lite_pkg::*;


  ////////////////////////////////////////////////////////////////
  //
  // Typedefs
  //
  typedef bit  [           7:0] octet;
  typedef bit  [DATA_WIDTH-1:0] data_type;
  typedef logic[ADDR_WIDTH-1:0] addr_type;


  ////////////////////////////////////////////////////////////////
  //
  // Tasks
  //

  /*
   * Read Intel HEX
   */
  task read_ihex;
    input string file;

    integer i;
    integer fd,
            cnt,
            eof;
    reg   [ 31:0] tmp;

    octet         byte_cnt;
    octet [  1:0] address;
    octet         record_type;
    octet [255:0] data;
    octet         checksum, crc;

    addr_type     base_addr=BASE;
    /*
     * 1: start code
     * 2: byte count  (2 hex digits)
     * 3: address     (4 hex digits)
     * 4: record type (2 hex digits)
     *    00: data
     *    01: end of file
     *    02: extended segment address
     *    03: start segment address
     *    04: extended linear address (16lsbs of 32bit address)
     *    05: start linear address
     * 5: data
     * 6: checksum    (2 hex digits)
     */

    fd = $fopen(file, "r"); //open file
    if (fd < 32'h8000_0000)
    begin
        $display ("ERROR  : Skip reading file %s. Reason file not found", file);
        $finish();
        return ;
    end

    eof = 0;
    while (eof == 0)
    begin
        if ($fscanf(fd, ":%2h%4h%2h", byte_cnt, address, record_type) != 3)
          $display ("ERROR  : Read error while processing %s", file);

        //initial CRC value
        crc = byte_cnt + address[1] + address[0] + record_type;

        for (i=0; i<byte_cnt; i++)
        begin
            if ($fscanf(fd, "%2h", data[i]) != 1)
              $display ("ERROR  : Read error while processing %s", file);

            //update CRC
            crc = crc + data[i];
        end

        if ($fscanf(fd, "%2h", checksum) != 1)
          $display ("ERROR  : Read error while processing %s", file);

        if (checksum + crc)
          $display ("ERROR  : CRC error while processing %s", file);

        case (record_type)
          8'h00  : begin
                       for (i=0; i<byte_cnt; i++)
                       begin
                           mem_array[ base_addr+address+ (i & ~(DATA_WIDTH/8 -1)) ][ (i%(DATA_WIDTH/8))*8+:8 ] = data[i];
$display ("write %2h to %8h (base_addr=%8h, address=%4h, i=%2h)", data[i], base_addr+address+ (i & ~(DATA_WIDTH/8 -1)), base_addr, address, i);
$display ("(%8h)=%8h",base_addr+address+4*(i/4), mem_array[ base_addr+address+4*(i/4) ]);
                       end
                   end
          8'h01  : eof = 1;
          8'h02  : base_addr = {data[0],data[1]} << 4;
          8'h03  : $display("INFO   : Ignored record type %0d while processing %s", record_type, file);
          8'h04  : base_addr = {data[0], data[1]} << 16;
          8'h05  : $display("ERROR  : Unsupported record type %0d while processing %s", record_type, file);
          default: $display("ERROR  : Unknown record type while processing %s", file);
        endcase
    end

    $fclose (fd);                //close file
  endtask


  /*
   * Read HEX generated by RISC-V elf2hex
   */
  task read_elf2hex;
    input string file;

    integer fd,
            i,
            line=0;
    reg [127:0] data;
    addr_type   base_addr = BASE;

    fd = $fopen(file, "r"); //open file
    if (fd < 32'h8000_0000)
    begin
        $display ("ERROR  : Skip reading file %s. File not found", file);
        $finish();
        return ;
    end
    else
      $display ("INFO   : Reading %s", file);

    //Read data from file
    while ( !$feof(fd) )
    begin
        line=line+1;
        if ($fscanf(fd, "%32h", data) != 1)
          $display("ERROR  : Read error while processing %s (line %0d)", file, line);

        for (i=0; i< 128/DATA_WIDTH; i++)
        begin
	    //$display("[%8h]:%8h",base_addr,data[i*DATA_WIDTH +: DATA_WIDTH]);
            mem_array[ base_addr ] = data[i*DATA_WIDTH +: DATA_WIDTH];
            base_addr = base_addr + (DATA_WIDTH/8);
        end
	
    end

    
    //close file
    $fclose(fd);
  endtask

  task print_memory;
    integer i;
    addr_type  base_addr = BASE;
    
    for(i = 0;i < 16; i++)
    begin
      if( i == 0) base_addr = BASE+ 'h10000; 
      else if (i == 8) base_addr = BASE + 'h12700;
      else base_addr = base_addr + DATA_WIDTH/2;

      $display("[%8h]: %8h, %8h, %8h, %8h", base_addr, mem_array[base_addr], mem_array[base_addr +4], mem_array[base_addr +8], mem_array[base_addr +12]);
    end
  endtask


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  integer i,j;
  genvar  p;

  localparam RADRCNT_MSB = $clog2(BURST) + $clog2(DATA_WIDTH/8)-1;

  data_type mem_array[addr_type];
  logic [ADDR_WIDTH   -1:0] iaddr [PORTS],
                            raddr [PORTS],
                            waddr [PORTS];
  logic [RADRCNT_MSB    :0] radrcnt [PORTS];

  logic                     wreq  [PORTS];
  logic [DATA_WIDTH/8 -1:0] dbe   [PORTS];

  logic [LATENCY        :1] ack_latency [PORTS];


  logic [              1:0] dHTRANS [PORTS];
  logic                     dHWRITE [PORTS];
  logic [              2:0] dHSIZE  [PORTS];
  logic [              3:0] dHBURST [PORTS];


  ////////////////////////////////////////////////////////////////
  //
  // Module body
  //

generate
  for (p=0; p<PORTS; p++)
  begin

      /*
       * Generate ACK
       */
     if (LATENCY > 0)
     begin
         always @(posedge HCLK,negedge HRESETn)
           if      (!HRESETn                   ) ack_latency[p] <= {LATENCY{1'b1}};
           else if (HREADY[p])
           begin
               if      ( HTRANS[p] == HTRANS_IDLE  ) ack_latency[p] <= {LATENCY{1'b1}};
               else if ( HTRANS[p] == HTRANS_NONSEQ) ack_latency[p] <= 'h0;
           end
           else                                      ack_latency[p] <= {ack_latency[p],1'b1};

         assign HREADY[p] = ack_latency[p][LATENCY];
     end
     else
         assign HREADY[p] = 1'b1;

      assign HRESP[p] = HRESP_OKAY;


      /*
       * Write Section
       */
      //delay control signals
      always @(posedge HCLK)
        if (HREADY[p])
        begin
            dHTRANS[p] <= HTRANS[p];
            dHWRITE[p] <= HWRITE[p];
            dHSIZE [p] <= HSIZE [p];
            dHBURST[p] <= HBURST[p];
        end

      always @(posedge HCLK)
        if (HREADY[p] && HTRANS[p] != HTRANS_BUSY)
        begin
            waddr[p] <= HADDR[p] & ( {DATA_WIDTH{1'b1}} << $clog2(DATA_WIDTH/8) );

            case (HSIZE[p])
               HSIZE_BYTE : dbe[p] <= 1'h1  << HADDR[p][$clog2(DATA_WIDTH/8)-1:0];
               HSIZE_HWORD: dbe[p] <= 2'h3  << HADDR[p][$clog2(DATA_WIDTH/8)-1:0];
               HSIZE_WORD : dbe[p] <= 4'hf  << HADDR[p][$clog2(DATA_WIDTH/8)-1:0];
               HSIZE_DWORD: dbe[p] <= 8'hff << HADDR[p][$clog2(DATA_WIDTH/8)-1:0];
            endcase
        end


     always @(posedge HCLK)
       if (HREADY[p]) wreq[p] <= (HTRANS[p] != HTRANS_IDLE & HTRANS[p] != HTRANS_BUSY) & HWRITE[p];


      always @(posedge HCLK)
        if (HREADY[p] && wreq[p])
          for (i=0; i<DATA_WIDTH/8; i++)
            if (dbe[p][i]) mem_array[waddr[p]][i*8+:8] = HWDATA[p][i*8+:8];
      /*
       * Read Section
       */
      assign iaddr[p] = HADDR[p] & ( {DATA_WIDTH{1'b1}} << $clog2(DATA_WIDTH/8) );


      always @(posedge HCLK)
        if (HREADY[p] && (HTRANS[p] != HTRANS_IDLE) && (HTRANS[p] != HTRANS_BUSY) && !HWRITE[p])
          if (iaddr[p] == waddr[p] && wreq[p])
          begin
              for (j=0; j<DATA_WIDTH/8; j++)
                if (dbe[p][j]) HRDATA[p][j*8+:8] <= HWDATA[p][j*8+:8];
                else           HRDATA[p][j*8+:8] <= mem_array[ iaddr[p] ][j*8+:8];
          end
          else
          begin
              HRDATA[p] <= mem_array[ iaddr[p] ];
          end
  end
endgenerate

endmodule
