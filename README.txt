Perl Call Graph Generator
=========================

This project provides a simple static analysis tool for examining the
interactions between subroutines in one or more perl scripts.

After scanning your code (including modules), a .dot file is generated, which
you can then turn into pretty (?) diagrams using a wonderful free peice of
software called GraphViz (http://www.graphviz.org)

The analysis is quite simplistic, but having a graphic diagram of the call
graph of your entire program, or just a selection of it, can be a great help,
even if it just helps you find the most likely places to look for whatever it
is you're looking for :-)

Installation:
=============

The script in this directory can be used as-is, there is no need to "install"
it anywhere special.

Documentation:
==============

The documentation for perl_call_graph.pl is embedded in the script as POD documentation.

Use your favourite pod2* script to convert it into your desired format. For example:

    pod2man perl_call_graph.pl | nroff -man | less

Workflow:
=========

    Normally it is enough to specifiy which functions you're interested in
    (via --start) and the files in question (ie: all .pm files)

            perl_call_graph.pl [--cluster] [--start <regex>] [--jpg|--png] <perl files>


Stephen Riehm
2011-10-19
