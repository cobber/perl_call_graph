#!/usr/local/bin/perl

# DESCRIPTION:  Perl call graph generator
#
#               This script analyzes one or more perl scripts or modules and
#               produces a GraphViz description file (in dot format)
#               Use GraphViz to convert the output file into a "pretty"
#               graphical representation of your code.
#
# AUTHOR:       Stephen Riehm
# Date:         2009-01-16

my $VERSION = '1.0';

use strict;
use warnings;
use Getopt::Long;       # command line processing
use Pod::Usage;

# TODO: use GraphViz
#       Sadly, it refuses to install on my Win2k Workstation :-(
#
# use GraphViz;           # for generating the actual call graph images

my $parameters = {};
my $got_opts   = GetOptions( $parameters, 'start=s', 'cluster!', 'help|?', );

pod2usage(2)        if $parameters->{'help'} or ! $got_opts;

my $start_node_regex = undef;

if( $parameters->{'start'} )
{
    $start_node_regex = qr/$parameters->{'start'}/i;
}

#
# scan all input files for anything that "looks like" a function definition or a function call.
# Function calls are recorded with their caller function,
#

my $current_file    = undef;
my $current_sub     = undef;
my $sub_definition  = {};
my $sub_call        = {};
my $call_graph      = {};

LINE:
while( my $line = <> )
{
    unless( defined $current_file )
    {
        $current_file   = $ARGV;
        $current_file   =~ s:.*[\\/]::; # only want the file name without path info
        $current_sub    = 'main';
    }

    $line =~ s/[\n\r]*$//;  # platform independent chomp

    next LINE if $line =~ /^\s*(#.*)?$/;  # skip empty lines and comments

    if( $line =~ /^\s*sub\s+(\w+)/ )
    {
        $current_sub = $1;
        $sub_definition->{$current_sub}{$current_file}{'line'} = $.;
        next LINE;
    }

    if( $line =~ /^}/ )
    {
        $current_sub = 'main';
        next LINE;
    }

    while( $line =~ s/^.*?(?<![$%@])(\w+)\s*\(// )
    {
        $sub_call->{$current_sub}{$current_file}{$1}++;
    }
}
continue
{
    if( eof )
    {
        close( ARGV );              # reset line numbers
        $current_file = undef;      # indicate that we've changed to a different file
    }
}

#
# try to match callers with callees
# first:    try to find a match within the same file.
# second:   see if the function is defined in ONE other file
# third:    complain about an ambiguous call if the callee has multiple definitions
#
foreach my $caller_sub ( keys %{$sub_call} )
{
    foreach my $caller_file ( keys %{$sub_call->{$caller_sub}} )
    {
        foreach my $referenced_sub ( keys %{$sub_call->{$caller_sub}{$caller_file}} )
        {
            # skip while(), for() and module calls
            next unless( exists $sub_definition->{$referenced_sub} );

            if( exists $sub_definition->{$referenced_sub}{$caller_file} )
            {
                $call_graph->{"$caller_file:$caller_sub"}{'invokes'}{"$caller_file:$referenced_sub"}++;
                $call_graph->{"$caller_file:$referenced_sub"}{'invoked_by'}{"$caller_file:$caller_sub"}++;
                next;
            }
            my ( @matching_definitions ) = sort keys %{$sub_definition->{$referenced_sub}};

            if( @matching_definitions == 1 )
            {
                my $referenced_file = shift @matching_definitions;
                $call_graph->{"$caller_file:$caller_sub"}{'invokes'}{"$referenced_file:$referenced_sub"}++;
                $call_graph->{"$referenced_file:$referenced_sub"}{'invoked_by'}{"$caller_file:$caller_sub"}++;
            }
            else
            {
                # print( "AMBIGUOS: $caller_file:$caller_sub() -> $referenced_sub() defined in @matching_definitions\n" );
            }
        }
    }
}

#
# determine which nodes to start graphing from
#
my @initial_nodes = ();
if( defined $start_node_regex )
{
    @initial_nodes = sort grep( /$start_node_regex/, keys %{$call_graph} );
}
else
{
    FILE_SUB:
    foreach my $file_sub ( sort keys %{$call_graph} )
    {
        unless( $call_graph->{$file_sub}{'invoked_by'} )
        {
            push( @initial_nodes, $file_sub );
            next FILE_SUB;
        }
    }
}

#
# Actually produce the graph
#
my $graph = graph->new(
                    'graph_name'    => 'perl_call_graph',
                    'call_graph'    => $call_graph,
                    'cluster_files' => $parameters->{'cluster'},
                    );

foreach my $file_sub ( @initial_nodes )
{
    $graph->plot( $file_sub );
}

$graph->generate_dot();

exit( 0 );

package graph;

sub new
{
    my $class = shift;
    my $self  = bless { @_ }, $class;

    return $self;
}

sub plot
{
    my $self            = shift;
    my $from_file_sub   = shift;
    my $direction       = shift || undef; # up, down or undefined

    $self->{'node'}{$from_file_sub}++;
    unless( defined $direction )
    {
        $self->{'initial_node'}{$from_file_sub}++;
        $direction = "up down";
    }

    if( $direction =~ /up/ )
    {
        foreach my $parent_file_sub ( sort keys %{$self->{'call_graph'}{$from_file_sub}{'invoked_by'}} )
        {
            $self->{'edge'}{$parent_file_sub}{$from_file_sub}++;
            $self->plot( $parent_file_sub, 'up' )    unless $self->{'node'}{$parent_file_sub}++;
        }
    }

    if( $direction =~ /down/ )
    {
        foreach my $to_file_sub ( sort keys %{$self->{'call_graph'}{$from_file_sub}{'invokes'}} )
        {
            $self->{'edge'}{$from_file_sub}{$to_file_sub}++;
            $self->plot( $to_file_sub, 'down' )    unless $self->{'node'}{$to_file_sub}++;
        }
    }
}

sub generate_dot
{
    my $self = shift;

    print <<_EO_HEADER;
digraph $self->{'graph_name'}
    {

    rankdir     = LR;   // layout from left to right
    concentrate = true; // concentrate overlapping lines
    ratio       = 0.7;  // make image 20% wider
    fontsize    = 24;

    node [ shape=Mrecord ];

_EO_HEADER

    print "\n\n    // nodes\n";

    my $indent = $self->{'cluster_files'} ? 8 : 4;
    my $cluster_file = '';
    foreach my $file_sub ( sort keys %{$self->{'node'}} )
    {
        my ( $file, $sub ) = split( /:/, $file_sub );

        if( $self->{'cluster_files'}
            and ( $cluster_file ne $file )
            )
        {
            # close the previous cluster
            printf( "       }\n" )      if $cluster_file;   # but only if there was a previous cluster

            $cluster_file = $file;

            print <<_EO_SECTION_HEADER;

    subgraph "cluster_$file"
        {
        label     = "$file";
        style     = "bold";
        fontname  = "Times-Bold";
        fontsize  = 48;
        fontcolor = "red";

_EO_SECTION_HEADER
    }

        my @node_attributes = ();

        push( @node_attributes, ( $self->{'cluster_files'}
                                    ? sprintf( "label = \"%s\"",      $sub )
                                    : sprintf( "label = \"%s | %s\"", $file, $sub )
                                    ) );

        push( @node_attributes, 'color = green' )   if exists $self->{'initial_node'}{$file_sub};

        printf( "%s%-40s [%s];\n",
                        ' ' x $indent,
                        "\"${file_sub}\"",
                        join( ", ", @node_attributes ),
                        );

    }

    if( $self->{'cluster_files'} )
        {
        printf( "       }\n" )      if $cluster_file;   # but only if there was a previous cluster
        }

    print "\n\n    // edges\n";

    foreach my $from_file_sub ( keys %{$self->{'edge'}} )
    {
        foreach my $to_file_sub ( keys %{$self->{'edge'}{$from_file_sub}} )
        {
            printf( "    %-40s -> %s;\n", "\"${from_file_sub}\"", "\"${to_file_sub}\"" );
        }
    }

    print "\n    }\n";
}

=head1 NAME

perl_call_graph.pl - generate a call graph in GraphViz' DOT format for a group of perl scripts or modules.

=head1 SYNOPSIS

1:  perl_call_graph.pl [--start=regex] [--[no]cluster] *.pl > graph.dot

2:  dot -Tjpg -o graph.jpg graph.dot

=head1 DESCRIPTION

This script scans all named perl scripts or modules for function definitions and calls.

If a starting point is defined, then any subroutines whose names match the
provided regular expression will be used as entry-points in the
resulting hierarchical graph. Additionally, the call graphs I<to> each starting
point are included in the digram.

If no starting point regex is defined, then any subroutine which is not called
from another subrountine in any of the files is considered to be an entry point.

Subroutines which are un-reachable from one of
the starting points are not included in the resulting graph.

Subroutines which are not defined in the files being parsed are NOT included in
the resulting graph.

Interactions between multiple files are automatically tracked also.

After generating the dot file, use one of the many graphviz tools to render a
nice graphical image of the filtered data.

=head OPTIONS

=over

=item --[no]cluster

Specifies that functions should be clustered on a file-by-file basis.

=item --start <regex>

Any function names that match <regex> are marked as entry-points. (Nodes with a green border.)

B<Note:> if other functions call the entry-points, they will also be displayed
(so they won't necessarily be on the left-hand edge of the resulting diagram).

B<Note:> don't use C<^> or C<$> in your regular expressions. The I<grepping> that
takes place internally covers both the file name and the function name. 
Use C<\b> instead, ie: C<--start '\bstart\b'>

By default, any functions which are not called by some other function are marked as entry points.


=back

=head1 EXAMPLES

To get an overview of YAML.pm, you might like to try some of the following:

    perl_call_graph.pl /usr/lib/site_perl/5.10.0/YAML.pm > yaml.dot

    perl_call_graph.pl /usr/lib/site_perl/5.10.0/YAML.pm /usr/lib/site_perl/5.10.0/YAML/*.pm > yaml.dot

    perl_call_graph.pl /usr/lib/site_perl/5.10.0/YAML.pm /usr/lib/site_perl/5.10.0/YAML/*.pm --cluster > yaml.dot

    perl_call_graph.pl /usr/lib/site_perl/5.10.0/YAML.pm /usr/lib/site_perl/5.10.0/YAML/*.pm --cluster --start dump > yaml.dot

    perl_call_graph.pl /usr/lib/site_perl/5.10.0/YAML.pm /usr/lib/site_perl/5.10.0/YAML/*.pm --cluster --start '\bdump\b' > yaml.dot

=head1 AUTHOR

Stephen Riehm <s.riehm@opensauce.de>

=head1 FEEDBACK

Please send bug reports or enhancemets: perl-feedback@opensauce.de

