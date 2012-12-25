package Zotero::Markdown;
use 5.010;
use Moo;

use MozRepl;
use JSON::Any;
use Path::Class;
use File::ShareDir;
use Try::Tiny;

# load javascript required for citation management
sub BUILD {
    my ($self) = @_;
    $self->run_file('citeproc.js');
}

has citations => (is => 'ro', default => sub {{}} );

has json_encoder => ( is => 'ro', default => sub { JSON::Any->new } );

has repl => (is => 'ro', lazy => 1, builder     => '_build_repl',);

has js_dir => (is => 'ro', default => sub {
                   return Path::Class::Dir
                       ->new(File::ShareDir::module_dir(__PACKAGE__))
                           ->subdir('js');
               } );

sub _build_repl {
    my $repl = MozRepl->new();
    $repl->setup({# zotero can be slow.
        client  => {extra_client_args => {timeout => 6000} },
    } );
    return $repl;
}

sub run {
    my ($self, @commands) = @_;
    my $result;
    $result = $self->repl->execute($_) for @commands;
    $result =~ s/^"|"$//g;
    try {
        my $obj = 
            return $self->json_encoder->jsonToObj($result)
        } catch {
            return $result;
        };
}

sub run_file {
    my ($self, $filename) = @_;
    local $/="\n\n"; # adjust input record sep;
    # to split into code paragraphs in an attempt to keep mozrepl happy
    my @code = $self->js_dir->file($filename)->slurp;
    return $self->run(@code);
}

sub parse_citation {
    my ($self, $cite ) = @_;
    return $self->citations->{$cite}
        if exists $self->citations->{$cite};
    my $rx = $self->citation_regex;
    $cite =~ /$rx/;
    my %parse;
    @parse{qw/author title year/} = @+{qw/author title year/};
    $self->citations->{$cite} = \%parse;
    return $self->citations->{$cite};
}


has citation_regex => ( is => 'ro',
                        default => sub {
                            qr/\(c\|               # preamble
                                (?<author>.*?)\s+  # author
                                (?<year>\d+)\s+    # year
                                (?<title>.*?)\)/x; # title fragment
                        });



sub search {
    my ($self, $cite) = @_;
    my %c = %{$self->parse_citation($cite)};
    # TODO - check search is done from "my library" not a collection.
    $self->run("var search = new zotero.Search();");
    # title contains $c->{title}
    $self->run(qq/search.addCondition("title", "contains", "$c{title}")/);
    # creator contains $c->{author}
    $self->run(qq/search.addCondition("creator", "contains", "$c{author}")/);
    # date contains $c->{year}
    $self->run(qq/search.addCondition("date", "is", "$c{year}")/);
    $self->run('var result = search.search()');
    my $results = $self->run('result.length');
    warn "More than one result returned for $cite.  Using the first one.\n"
        if $results > 1;
    return $self->run("result[0]");
}

sub get_available_styles {
    my ($self) = @_;
    my $js = '
        var styles = zotero.Styles.getVisible();
        var style_info = [];
        for each ( var s in styles) {
            style_info.push( { "id" : s.styleID, "name" : s.title } );
        }
        JSON.stringify(style_info);
        ';

    my $styles = $self->run($js);
    my %styles;
    foreach my $s (@$styles) {
        $styles{$s->{name}} = $s->{id};
    }
    return \%styles;
}




1;
__END__
=head1 NAME

Zotero::Markdown

=head2 DESCRIPTION

Package for handling human readable Author/Date citations in markdown format.
Designed to be good enough for common use cases, not perfect.

=head2 SYNOPSIS

Will scan a plain text document paragraph by paragraph for citations using
a human readable format to key citations.  Conversion will die without
modifying the document if there are ambiguous citation keys.

Examples of the format are

 (c|Fletcher 2003 Mapping stakeholder perceptions)
 (c|Law 2008 On sociology)

You can put perl regex elements into the title portion.  e.g. ^, $,
.*

=head2 citations

hashref of citations seen during document processing, keyed by the
citation text provided by the user.  Used to memoize

=head2 repl

MozRepl object for internal use

=head2 run

sends javascript commands to the repl and returns the result of the last
command.

=head2 run_file

Reads in javascript source code, and sends it to the repl paragraph by
paragraph(delimited by \n\n).  WARNING - be sure to ensure that each
paragraph compiles as a standalone entity.  If not the repl will hang then
time out.

=head2 parse_citation

parses the citation to author title and year hashref

=head2 citation_regex

Simple regex for parsing the text string.
TODO.  consider making a proper parser.
TODO.  consider optional doi support.

