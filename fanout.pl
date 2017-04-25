#!/usr/bin/perl -w

# Ameer Abdelhadi
# fanout.pl:
#   generates a Comma-Separated Values (CSV) file of all nodes in a given
#   Verilog Quartus Mapping (VQM) netlist and their respective fanouts,
#   ordered by fanout (highest first).
#   * Verilog include files contain declarations of all modules present in
#     the VQM shall be provided.
#   * Assign statements are treated as though they were single
#     input-single output gates.
#   * Unconnected wires (*_unconnected_wire_*) and power supplies
#     (vcc, gnd) are ignored.
#
# Usage:
#  ./fanout.pl <VQM input netlist file name (mandatory)> \
#              <CSV file name, listing "node,fanout" pairs (mandatory)> \
#              [Verilog include file 1 (optional)] \
#              [Verilog include file 2 (optional)] \
#              [Verilog include file 3 (optional)] ...
# 
# Usage example: 
#   ./fanout.pl fp_pow.vqm fp_pow_fo.csv sim/altera_primitives.v sim/cyclonev_atoms.v
#
# CSV output example:
#   net_a,1000
#   net_b,999
#   net_c,100

use Storable;      # Allow storage of data structures (e.g. hash) into disk
use File::Basename;
use strict;        # Install all strictures
use warnings;      # Show warnings
$|++;              # Force auto flush of output buffer

###############################################################################

# parseInclude: Parse Verilog include files with module declaration
# arguments: include file path, include file name, include file type
# returns a 2D hash with:
#   keys : module name as 1st key & port name as 2nd key
#   value: port direction, "i" if input, "o" if output
sub parseInclude {
  
  # read arguments
  my $include_fname = shift;
  # extract the include file name base
  $include_fname =~ /([^\/]*)\.[^\.]*$/;
  my $include_fname_base = $1;
  # include hash reference
  my $include_href;
  # include hash, to be returned
  my %include_hash;

  # if stored hash exists on disk, retrieve it, then return
  if (-e "$include_fname_base.hash") {
    $include_href = retrieve("$include_fname_base.hash");
    %include_hash = %$include_href;
    return %include_hash;
  }

  # if the hash is not stored on disk, generate it
  # read the include file
  open(include_handler,"$include_fname") || die "-E- Can't open $include_fname";
  # read file lines in an array
  my @include_lines = <include_handler>;
  # remove trailing end line markers (\n)
  chomp(@include_lines);
  close(include_handler);

  # iterate over all include file lines
  my $i=0;
  while ($i<$#include_lines) {
    
    # if module declaration is detected,
    if ($include_lines[$i] =~ /^\s*module\s*(\S*)\(?/) {
      my $module = $1;
      $i++;
      # wait until endmodule declaration is detected
      while ($include_lines[$i] !~ /^\s*endmodule\s*/) {
        # if input pin declaration is detected,
        if ($include_lines[$i] =~ /^\s*input\s*(.*)\s*;/)  {
          # comma-split all input pins into an array
          my @inputs=split(/\s*\,\s*/,$1);
          # add each of these input pins into the hash as 'i'
          foreach my $input (@inputs) {
            # remove bit range declaration
            if ($input =~ /\[.*\]\s*(\S+)/) {$input = $1}
            $include_hash{$module}{$input}='i';
          }
        }
        # otherwise, if output pin declaration is detected,
        elsif ($include_lines[$i] =~ /^\s*output\s*(.*)\s*;/) {
          # comma-split these output pins into an array
          my @outputs=split(/\s*\,\s*/,$1);
          # add each of these output pins into the hash as 'o'
          foreach my $output (@outputs) {
            # remove bit-range declaration
            if ($output =~ /\[.*\]\s*(\S+)/) {$output = $1}
            $include_hash{$module}{$output}='o';
          }
        }
        $i++;
      } # endmodule
    }
    $i++;
  } # eof

  # store hash on disk & return hash structure
  store(\%include_hash,"$include_fname_base.hash");
  return %include_hash;
}

###############################################################################

# parseNetlist: Parse Verilog netlist file to count fanout of each node
# arguments: netlist file path, netlist file name, netlist file type, list of references to all include hashes
# returns a 1D hash with:
#   keys : internal node in the netlist
#   value: fanout
sub parseNetlist {

  # read arguments
  my ($netlist_fname,$include_href) = @_;
  my %include_hash = %$include_href;

  # the netlist hash, to be returned
  my %netlist_hash;
  # open the verilog netlist file for reading
  open(netlist_handler,"$netlist_fname") || die "-E- Can't open $netlist_fname";
  # read the verilog netlist file into an array
  my @netlist_lines = <netlist_handler>;
  close(netlist_handler);

  # set Input Record Separator ($/) to new line (\n) carriage return (\r) in case for dos-formatted files, to be removed by chomp
  local $/ = "\r\n";
  # remove trailing \r and \n
  chomp(@netlist_lines);

  # remove comments and empty line from the netlist
  @netlist_lines = grep { ! /^\s*\/\/|^\s*$/ } @netlist_lines;
  # concatenate all netlist lines, them semi-comma-split
  @netlist_lines = split(/\s*\;\s*/,"@netlist_lines");

  # iterate over all netlist lines
  for (my $i=0; $i<$#netlist_lines; $i++) {
    # ignore module, input, output, wire, and defparam statements
    if ($netlist_lines[$i] =~ /^\s*module\s*|^\s*input\s*|^\s*output\s*|^\s*wire\s*|^\s*defparam\s*/) {next}
    # for assign statements, increment the fanout of the second argument
    if ($netlist_lines[$i] =~ /assign\s*(\S*)\s*\=\s*\~?\s*(\S*)/) {
      if ($2 !~ /_unconnected_wire_|^\\?vcc$|^\\?gnd$/) {$netlist_hash{$2}++;}
      next;
    }
    # for instantiation statements, detect ports list and direction of ports to increment fanout of input ports
    if ($netlist_lines[$i] =~ /^(\S*)\s*\S*\s*\(\s*\.(.*)\s*\)\s*$/) {
      my $module=$1;
      # dot-split ports list
      my @ports=split(/\s*\.\s*/,$2);
      # for each port of the ports list
      foreach my $port (@ports) {
        # remove leading '{' and trailing '}', if they exist
        $port =~ /(.*)\(\s*\{?\s*([^\}]*)\s*\}?\s*\)/;
        # detect module pin name and the wire connected to it
        my $pin = $1;
        my $wire = $2;
        # if the wire is a vector, split it (comma-split)
        my @wire_bits = ($wire);
        if ($wire =~ /\,/) {@wire_bits = split(/\s*\,\s*/,$wire)}
        # for each bit in the vector
        foreach my $wire_bit (@wire_bits) {
          # remove leading and trailing spaces
          $wire_bit =~ s/^\s+|\s+$//g;
          # find the direction of the pin (if exists), if input pin, increment the fanout
          if (exists($include_hash{$module}{$pin})) {
            # find pin direction from the include hash
            my $dir = $include_hash{$module}{$pin};
            # if input pin, increment the fanout
            if ($dir eq "i") {
                    if ($wire_bit !~ /_unconnected_wire_|^\\?vcc$|^\\?gnd$/) {$netlist_hash{$wire_bit}++;}
            }
          } else {die "-E- pin $pin of module $module is undefined"};
        }
      }
    }
  }
  # retun the netlist hash including nodes as keys and fanouts as values
  return %netlist_hash;
}

###############################################################################

# hash2csv: prints hash key and value into a csv file, sorted by values
# arguments: csv file path, csv file name, csv file type, z references to the netlist fanout hash
sub hash2csv {
    # read arguments
    my ($csv_fname,$netlist_fo_href) = @_;
    # link fanouts hash to hash reference
    my %netlist_fo = %$netlist_fo_href;
    # open the csv file for writing
    open(my $csv_handler, '>', "$csv_fname") || die "-E- Could not open file $csv_fname for writing $!";
    # write keys (nodes) and values (fanouts) to the csv file, sorted by values (fanouts)
    foreach my $node (sort { $netlist_fo{$b} <=> $netlist_fo{$a} } keys %netlist_fo) {
      print $csv_handler "$node,$netlist_fo{$node}\n";
    }
}

###############################################################################

# printHelp: prints help message, followed by the subroutine arguments then terminates the script
# arguments: error message
sub printHelp {
print STDERR <<EOF;
fanout.pl:
  generates a Comma-Separated Values (CSV) file of all nodes in a given
  Verilog Quartus Mapping (VQM) netlist and their respective fanouts,
  ordered by fanout (highest first).
  * Verilog include files contain declarations of all modules present in
    the VQM shall be provided.
  * Assign statements are treated as though they were single
    input-single output gates.
  * Unconnected wires (*_unconnected_wire_*) and power supplies
    (vcc, gnd) are ignored.

Usage:
  ./fanout.pl <VQM input netlist file name (mandatory)> \
              <CSV file name, listing "node,fanout" pairs (mandatory)> \
              [Verilog include file 1 (optional)] \
              [Verilog include file 2 (optional)] \
              [Verilog include file 3 (optional)] ...
 
Usage example: 
  ./fanout.pl fp_pow.vqm fp_pow_fo.csv sim/altera_primitives.v sim/cyclonev_atoms.v

CSV output example:
  net_a,1000
  net_b,999
  net_c,100

@_
EOF
exit;
}

###############################################################################
# MAIN SCRIPT
###############################################################################

# read arguments
my $netlist_fname  = shift(@ARGV) || printHelp("-E- input netlist file name is missing");
my $csv_fname      = shift(@ARGV) || printHelp("-E- output csv file name is missing"   );
my @include_fnames = @ARGV;

# generate a hash (%include_hash) from Verilog include files
# This is a 2D hash with:
#   keys : module name as 1st key & port name as 2nd key
#   value: port direction, "i" if input, "o" if output
my %include_hash = ();
foreach my $include_fname (@include_fnames) {
  %include_hash = (%include_hash,parseInclude($include_fname));
}

# parse the netlist and count the fanout of each internal node
# generates a hash where the internal nodes are the keys and the fanouts are the value
my %netlist_fanout    = parseNetlist($netlist_fname,\%include_hash);

# write a csv file of the netlist fanouts hash, sorted by values (fanouts)
hash2csv($csv_fname,\%netlist_fanout);

