#!/usr/bin/env perl

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
use 5.8.8;
use Getopt::Long;       # command line processing
use Pod::Usage;
use GraphViz;           # for generating the actual call graph images
use POSIX qw( strftime );

my $start_node_regex = undef;
my @ignore_patterns  = ();

my $parameters = {
    'ignore' => [],     # may be specified multiple times
    };
my $got_opts = GetOptions( $parameters,
    'cluster!',
    'help|?',
    'man',
    'ignore=s',
    'output=s',
    'start=s',
    # output formats
    'dot',
    'svg',
    'jpg',
    'png',
    );

pod2usage( -verbose => 0, -exit => 0 )  if $parameters->{'help'} or ! $got_opts;
pod2usage( -verbose => 2, -exit => 0 )  if $parameters->{'man'};

if( $parameters->{'start'} )
    {
    $start_node_regex = qr/$parameters->{'start'}/i;
    }

foreach my $ignore_pattern ( @{$parameters->{'ignore'}} )
    {
    push( @ignore_patterns, qr/$ignore_pattern/i );
    }

$parameters->{'output'} ||= '.';
if( -d $parameters->{'output'} )
    {
    my $base_name = 'call_graph_';
    if( $parameters->{'start'} )   
        {
        $base_name .= $parameters->{'start'};
        $base_name =~ s/\\.//g;
        $base_name =~ s/[^-\w]//g;
        }
    else
        {
        $base_name .= strftime( "%Y%m%d-%H%M%S", localtime() );
        }
    $parameters->{'output'} =~ s:/*$:/$base_name:;
    }

if( not -e $parameters->{'output'} and $parameters->{'output'} =~ s/\.(dot|svg|jpg|png)$// )
    {
    $parameters->{$1} = 1;
    }

# generate dot files by default
$parameters->{'dot'}      = 1   unless grep( defined, @{$parameters}{qw( dot svg jpg png )} );

#
# scan all input files for anything that "looks like" a function definition or a function call.
# Function calls are recorded with their caller function,
#

my $current_file    = undef;
my $current_sub     = undef;
my $sub_definition  = {};
my $sub_call        = {};
my $call_graph      = {};
my $in_pod          = 0;

die "Please specify some files to parse!\n" unless @ARGV;

# TODO: replace this with a real perl parser (ha!) which properly handles
# matching curlies, pod documentation etc.
LINE:
while( my $line = <> )
    {
    unless( defined $current_file )
        {
        $current_file   = $ARGV;
        #         $current_file   =~ s:.*[\\/]::; # only want the file name without path info
            $current_sub    = 'main';
        }

    $line =~ s/[\n\r]*$//;  # platform independent chomp

    next LINE if $line =~ /^\s*(#.*)?$/;  # skip empty lines and comments

    # skip pod documentation
    if( $line =~ /^=(\w+)/ )
        {
        $in_pod = ( $1 eq 'cut' ) ? 0 : 1;
        next LINE;
        }

    next LINE   if $in_pod;

    # look for sub <...>
    # but ignore lines which don't look like a real sub (ie: 'sub blah foo')
    if( $line =~ /^\s*sub\s+(\w+)(?:\s*?(?:[#{].*)?)$/ )
        {
        $current_sub = $1;
        $sub_definition->{$current_sub}{$current_file}{'line'} = $.;
        next LINE;
        }

    # TODO: reliably recognise the end of a sub
    # how about 'everything between the last closing curly and the current sub'? (re-evaluate calls)
    if( $line =~ /^}/ )
        {
        $current_sub = 'main';
        next LINE;
        }

    # TODO: extend to do clever things with method calls
    # for example:
    #   CLASS::SUBCLASS->foo()      file can be derived
    #   $var->foo()                 may match multiple classes
    #   $var->foo
    #   {$var->{method}}->foo
    # currently - this is deliberatly very lenient - because we don't care
    # about calls which don't match to a subroutine in one of the files that
    # were provided
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
            next if( grep $referenced_sub =~ /$_/, @ignore_patterns );

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
                    'call_graph'        => $call_graph,
                    'output_base_name'  => $parameters->{'output'},
                    'cluster_files'     => $parameters->{'cluster'},
                    'generate_dot'      => $parameters->{'dot'},
                    'generate_svg'      => $parameters->{'svg'},
                    'generate_jpg'      => $parameters->{'jpg'},
                    'generate_png'      => $parameters->{'png'},
                    );

foreach my $file_sub ( @initial_nodes )
    {
    $graph->plot( $file_sub );
    }

$graph->generate();

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

sub generate
    {
    my $self = shift;

    my $graph = GraphViz->new(
                                rankdir     => 1,       #  1 = left to right, 0 = top to bottom
                                concentrate => 1,       #  concentrate overlapping lines
                                ratio       => 0.7,     #  make the image 20% wider
                                fontsize    => 24,      # was 24
                                node        => { shape => 'Mrecord', },
                            );

    foreach my $file_sub ( sort keys %{$self->{'node'}} )
        {
        my ( $file, $sub ) = split( /:/, $file_sub );
        my $cluster_id     = "cluster_$file";

        if( $self->{'cluster_files'} and not $self->{'clusters'}{$cluster_id} )
            {
            $self->{'clusters'}{$cluster_id} = {
                label     => $file,
                style     => "bold",
                fontname  => "Times-Bold",
                fontsize  => 48,        # was 48
                fontcolor => "red",
                };
            }

        my %node_attributes = ();

        $node_attributes{'label'} = $self->{'cluster_files'}
            ? sprintf( "%s",     $sub )
            : sprintf( "%s\n%s", $file, $sub )
            ;

        # highlight the start node(s)
        if( exists $self->{'initial_node'}{$file_sub} )
            {
            $node_attributes{'style'}     = 'filled';
            $node_attributes{'fillcolor'} = '/greens3/2'; # background, first green in greens3 colorscheme
            $node_attributes{'color'}     = '/greens3/3'; # border, last green in greens3 colorscheme
            }
        $node_attributes{'cluster'} = $self->{'clusters'}{$cluster_id}  if $self->{'cluster_files'};

        $graph->add_node( $file_sub, %node_attributes );
        }

    foreach my $from_file_sub ( keys %{$self->{'edge'}} )
        {
        foreach my $to_file_sub ( keys %{$self->{'edge'}{$from_file_sub}} )
            {
            $graph->add_edge( $from_file_sub, $to_file_sub );
            }
        }

    if( $self->{'generate_png'} )
        {
        if( $graph->can( 'as_png' ) )
            {
            printf "Generating: %s\n", $self->{'output_base_name'} . '.png';
            $graph->as_png(  $self->{'output_base_name'}.'.png' )
            }
        else
            {
            printf "The installed GraphViz doesn't support PNG\n";
            $self->{generate_jpg} = 1;
            }
        }
    if( $self->{'generate_jpg'} )
        {
        if( $graph->can( 'as_jpg' ) )
            {
            printf "Generating: %s\n", $self->{'output_base_name'} . '.jpg';
            $graph->as_jpg(  $self->{'output_base_name'}.'.jpg' ) 
            }
        else
            {
            printf "The installed GraphViz doesn't support JPG\n";
            $self->{generate_dot} = 1;
            }
        }
    if( $self->{'generate_svg'} )
        {
        if( $graph->can( 'as_svg' ) )
            {
            printf "Generating: %s\n", $self->{'output_base_name'} . '.svg';
            $graph->as_svg(  $self->{'output_base_name'}.'.svg' ) 
            }
        else
            {
            printf "The installed GraphViz doesn't support svg\n";
            $self->{generate_dot} = 1;
            }
        }
    if( $self->{'generate_dot'} )
        {
        printf "Generating: %s\n", $self->{'output_base_name'} . '.dot';
        $graph->as_text( $self->{'output_base_name'}.'.dot' )
        }
    }

=head1 NAME

perl_call_graph.pl - generate a call graph in GraphViz' DOT format for a group of perl scripts or modules.

=head1 SYNOPSIS

=head2 Graph as image:

    % perl_call_graph [--[no]cluster] [--start <regex>] [--ignore <regex>...] [--output <dir|file>] [--[png|jpg|svg]] *.pm

=head2 Graph as DOT file (manual image creation via GraphViz):

    % perl_call_graph [--[no]cluster] [--start=regex] [--ignore <regex>] [--output <dir|file>] *.pm
    % dot -Tjpg -o graph.jpg <outputfile>

=head2 Full help:

    % perl_call_graph --man

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

=head1 WARNING

This script does not perform full-blown static code analysis. Rather, it scans
the provided source code for function definitions and calls.

As a result, it can be confused by sample code in comments and it is not able
to accurately model object-oriented interactions.

=head1 OPTIONS

=over

=item --start <regex>

Any function names that match <regex> are marked as entry-points. (Nodes with a green border.)

B<Note:> if other functions call the entry-points, they will also be displayed
(so they won't necessarily be on the left-hand edge of the resulting diagram).

B<Note:> don't use C<^> or C<$> in your regular expressions. The I<grepping> that
takes place internally covers both the file name and the function name. 
Use C<\b> instead, ie: C<--start '\bstart\b'>

By default, any functions which are not called by some other function are marked as entry points.

=item --ignore <regex>

Ignore functions which match <regex>.

C<--ignore> may be specified multiple times to ignore multiple sub-graphs

=item --[no]cluster

Specifies that functions should be clustered on a file-by-file basis.

=item --output <directory>

=item --output <filename>

Specify where the output should be written.

If a directory is specified, then the --start specification will be used to
derive a file name. In these cases the file name will have the following structure:

    'call_graph_' <start_pattern> '.' <format>

Note that all non-alphanumeric characters will be replaces by a single
underscore, so C<--start '\w*create\w*view' -jpg> would generate the file name:
C<call_graph_create_view.jpg>

If a filename is specified then the file will be created or overwritten as necessary.

Default: <current directory>

=item --dot

Generate a DOT file which can be given to GraphViz for formatting into any graphical format.

This is the default output format.

=item --svg

Generate a svg image of the resulting call graph.

=item --jpg

Generate a jpg image of the resulting call graph.

Only available if the graphviz and jpg libraries have been installed

=item --png

Generate a png image of the resulting call graph.

Only available if the graphviz and png libraries have been installed

=back

=head1 EXAMPLES

To get an overview of YAML.pm, you might like to try some of the following:

    perl_call_graph.pl -png                              /usr/lib/site_perl/5.10.0/YAML.pm

    perl_call_graph.pl -png                              /usr/lib/site_perl/5.10.0/YAML.pm /usr/lib/site_perl/5.10.0/YAML/*.pm

    perl_call_graph.pl -png --cluster                    /usr/lib/site_perl/5.10.0/YAML.pm /usr/lib/site_perl/5.10.0/YAML/*.pm
                                                         
    perl_call_graph.pl -png --cluster --start dump       /usr/lib/site_perl/5.10.0/YAML.pm /usr/lib/site_perl/5.10.0/YAML/*.pm
                                                         
    perl_call_graph.pl -png --cluster --start '\bdump\b' /usr/lib/site_perl/5.10.0/YAML.pm /usr/lib/site_perl/5.10.0/YAML/*.pm

=head1 AUTHOR

Stephen Riehm <s.riehm@opensauce.de>

=head1 FEEDBACK

Please send bug reports or enhancemets: perl-feedback@opensauce.de

