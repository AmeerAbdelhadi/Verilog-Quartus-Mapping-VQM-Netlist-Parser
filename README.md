## Verilog-Quartus-Mapping-VQM-Netlist-Parser ##
### Ameer Abdelhadi; April 2017 ###

<BR>

## fanout.pl: ##
  Generates a Comma-Separated Values (CSV) file of all nodes in a given Verilog Quartus Mapping (VQM) netlist and their respective fanouts, ordered by fanout (highest first).
  * Verilog include files contain declarations of all modules present in the VQM shall be provided.
  * Assign statements are treated as though they were single input-single output gates.
  * Unconnected wires (*_unconnected_wire_*) and power supplies (vcc, gnd) are ignored.

## Usage: ##
```
  ./fonout.pl <VQM input netlist file name (mandatory)> \
              <CSV file name, listing "node,fanout" pairs (mandatory)> \
              [Verilog include file 1 (optional)] \
              [Verilog include file 2 (optional)] \
              [Verilog include file 3 (optional)] ...
```

## Usage example: ##
  `./fanout.pl fp_pow.vqm fp_pow_fo.csv sim/altera_primitives.v sim/cyclonev_atoms.v`

## CSV output example: ##
```
  net_a,1000
  net_b,999
  net_c,100
```
## Files and directories in this package: ##
  * **fanout.pl:** Main script: Verilog Quartus Mapping (VQM) netlist parser; lists fanout of internal nodes
  * **fp_pow.vqm:** Example of a Verilog Quartus Mapping (VQM) netlist
  * **fp_pow_fo.csv:** Output CSV file listing "node,fanout" pairs for fp_pow.vqm example
  * **sim/:** Contains include files
  * **sim/altera_primitives.v:** Contains the behavioral models for Altera primitives
  * **sim/cyclonev_atoms.v:** Contains the behavioral models for Altera Cyclone V device primitives

