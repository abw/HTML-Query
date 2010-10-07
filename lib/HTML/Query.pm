package HTML::Query;

our $VERSION = '0.04';

use Badger::Class
    version   => $VERSION,
    debug     =>  0,
    base      => 'Badger::Base',
    utils     => 'blessed',
    import    => 'class CLASS',
    vars      => '$error AUTOLOAD',
    constants => 'ARRAY',
    constant  => {
        ELEMENT => 'HTML::Element',
        BUILDER => 'HTML::TreeBuilder',
    },
    exports   => {
        any   => 'Query',
        hooks => {
            query => \&_export_query_to_element,
        },
    },
    messages  => {
        no_elements => 'No elements specified to query',
        no_query    => 'No query specified',
        no_source   => 'No argument specified for source: %s',
        bad_element => 'Invalid element specified: %s',
        bad_source  => 'Invalid source specified: %s',
        bad_query   => 'Invalid query specified: %s',
        bad_spec    => 'Invalid specification "%s" in query: %s',
        is_empty    => 'The query does not contain any elements',
    };


our $SOURCES = {
    text => sub {
        class(BUILDER)->load;
        BUILDER->new_from_content(shift);
    },
    file => sub {
        class(BUILDER)->load;
        BUILDER->new_from_file(shift);
    },
    tree => sub {
        $_[0]
    },
    query => sub {
        ref $_[0] eq ARRAY
            ? @{ $_[0] }
            :    $_[0];
    },
};

#our $error; # how can we store this in the class itself? this is stupid...


sub _export_query_to_element {
    class(ELEMENT)->load->method(
        # this Just Works[tm] because first arg is HTML::Element object
        query => \&Query,
    );
}

sub _report_error {
    my ($self, $message) = @_;

    if (suppress_errors()) {
      if (defined($message)) { 
        $error = $message;
      }
      return undef;
    }
    else {
      $self->error($message);
    }
}

sub Query (@) {
    CLASS->new(@_);
}


sub new {
    my $class = shift;
    my ($element, @elements, $type, $code, $select);

    # expand a single list ref into items
    unshift @_, @{ shift @_ }
        if @_ == 1 && ref $_[0] eq ARRAY;

    $class = ref $class || $class;

    # each element should be an HTML::Element object, although we might
    # want to subclass this module to recognise a different kind of object,
    # so we get the element class from the ELEMENT constant method which a
    # subclass can re-define.
    my $element_class = $class->ELEMENT;

    while (@_) {
        $element = shift;
        $class->debug("argument: ".$element) if DEBUG;

        if (! ref $element) {
            # a non-reference item is a source type (text, file, tree)
            # followed by the source, or if it's the last argument following
            # one ore more element options or named argument pairs then it's
            # a selection query
            if (@_) {
                $type = $element;
                $code = $SOURCES->{ $type }
                    || return $class->error_msg( bad_source => $type );
                $element = shift;
                $class->debug("source $type: $element") if DEBUG;
                unshift(@_, $code->($element));
                next;
            }
            elsif (@elements) {
                $select = $element;
                last;
            }
        }
        elsif (blessed $element) {
            # otherwise it should be an HTML::Element object or another
            # HTML::Query object
            if ($element->isa($element_class)) {
                push(@elements, $element);
                next;
            }
            elsif ($element->isa($class)) {
                push(@elements, @$element);
                next;
            }
        }

        return $class->error_msg( bad_element => $element );
    }

    my $self = bless \@elements, $class;

    return defined $select
        ? $self->query($select)
        : $self;
}

sub suppress_errors {
    my ($self, $setting) = @_;

    our $suppress;

    if (defined($setting)) {
      $suppress = $setting;
    }

    return $suppress;
}

sub get_error {
    my ($self) = @_;

    return $error;
}

sub query {
    my ($self, $query) = @_;
    my @result;
    my $ops = 0;
    my $pos = 0;

    $error = undef;

    return $self->error_msg('no_query')
        unless defined $query
            && length  $query;

    # multiple specs can be comma separated, e.g. "table tr td, li a, div.foo"
    COMMA: while (1) {
        # each comma-separated traversal spec is applied downward from
        # the source elements in the @$self query
        my @elements = @$self;
        my $comops   = 0;

        # for each whitespace delimited descendant spec we grok the correct
        # parameters for look_down() and apply them to each source element
        # e.g. "table tr td"
        SEQUENCE: while (1) {
            my @args;
            my %seen;
            my @unique;
            $pos = pos($query) || 0;
            my $relationship = '';
            my $leading_whitespace;
            my $universal = '';

            warn "Starting new SEQUENCE" if DEBUG;

            # ignore any leading whitespace
            if ($query =~ / \G (\s+) /cgsx) {
              $leading_whitespace = defined($1) ? 1 : 0;
            }

            # grandchild selector is whitespace sensitive, requires leading whitespace
            if ($leading_whitespace && $comops && ($query =~ / \G (\*) \s+ /cgx)) {
              # can't have a relationship modifier as the first part of the query
              $relationship = $1;
              warn "relationship = $relationship\n" if DEBUG;
            }

            # get other relationship modifiers
            if ($query =~ / \G (>|\+) \s* /cgx) {
              # can't have a relationship modifier as the first part of the query
              $relationship = $1;
              warn "relationship = $relationship\n" if DEBUG;
              if (!$comops) {
                return $self->_report_error( $self->message( bad_spec => $relationship, $query ) );
              }
            }

                # optional leading word is a tag name - handle malformed universal/grandchild selector here
                # make sure not to match standalone universal selector - that comes later!
                # TODO double check this regex, I don't understand it, it's from Dave
                if ($query =~ / \G(?!\*(?:\s+|$|\[))([\w*]+) /cgx) {
                    my $tag = $1;

                    if ($tag =~ m/\*/) {
                        return $self->_report_error( $self->message( bad_spec => $tag, $query ) );
                    }

                    push( @args, _tag => $tag );
                }

                # universal selector, requires leading whitespace or to be first operator
                if (($leading_whitespace || $comops == 0) && ($query =~ / \G (\*) /cgx)) {

                    #select all tags from this point down
                    push(@args, _tag => qr/\w+/);
                }

            # loop to collect a description about this specific part of the rule
            while (1) {
                my $work = scalar @args;

                # that can be followed by (or the query can start with) a #id
                if ($query =~ / \G \# ([\w\-]+) /cgx) {
                    push( @args, id => $1 );
                }

                # and/or a .class
                if ($query =~ / \G \. ([\w\-]+) /cgx) {
                   push( @args, class => qr/ (^|\s+) $1 ($|\s+) /x );
                }

                # and/or none or more [ ] attribute specs
                while ($query =~ / \G \[ (.*?) \] /cgx) {
                    my $attribute = $1;

                    #if we have an operator
                    if ($attribute =~ m/(.*?)\s*([\|\~]?=)\s*(.*)/) {
                        my ($name,$attribute_op,$value) = ($1,$2,$3);
                        warn "operator $attribute_op" if DEBUG;

                        if (defined $value) {
                            for ($value) {
                                s/^['"]//;
                                s/['"]$//;
                            }
                            if ($attribute_op eq '=') {
                                push( @args, $name => $value);
                            }
                            elsif ($attribute_op eq '|=') {
                                push(@args, $name => qr/\b${value}-?/)
                            }
                            elsif ($attribute_op eq '~=') {
                                push(@args, $name => qr/\b${value}\b/)
                            }
                        }
                    }
                    else {
                        # add a regex to match anything (or nothing)
                        push( @args, $attribute => qr/.*/ );
                    }
                }

                # keep going until this particular expression is fully processed
                last unless scalar(@args) > $work;
            }

            # we must have something in @args by now or we didn't find any
            # valid query specification this time around
            last SEQUENCE unless @args;

            $self->debug(
                'Parsed ', substr($query, $pos, pos($query) - $pos),
                ' into args [', join(', ', @args), ']'
            ) if DEBUG;

            # we're just looking for any descendent
            if( !$relationship ) {
              # look_down() will match self in addition to descendents,
              # so we explicitly disallow matches on self as we iterate
              # thru the list.  The other cases below already exclude self.
              # https://rt.cpan.org/Public/Bug/Display.html?id=58918
              my @accumulator;
              foreach my $e (@elements) {
                push(@accumulator, grep { $_ != $e } $e->look_down(@args));
              }

              @elements = @accumulator;
            }
            # immediate child selector
            elsif( $relationship eq '>' ) {
              @elements = map {
                $_->look_down(
                  @args,
                  sub {
                    my $tag = shift;
                    my $root = $_;

                    return $tag->depth == $root->depth + 1;
                  }
                )
              } @elements;
            }
            # immediate sibling selector
            elsif( $relationship eq '+' ) {
              @elements = map {
                $_->parent->look_down(
                  @args,
                  sub {
                    my $tag = shift;
                    my $root = $_;
                    my @prev_sibling = $tag->left;
                    # get prev next non-text sibling
                    foreach my $sibling (reverse @prev_sibling) {
                      next unless ref $sibling;
                      return $sibling == $root;
                    }
                  }
                )
              } @elements;
            }
            # grandchild selector
            elsif( $relationship eq '*' ) {
              @elements = map {
                $_->look_down(
                  @args,
                  sub {
                    my $tag = shift;
                    my $root = $_;

                    return $tag->depth > $root->depth + 1;
                  }
                )
              } @elements;
            }

            # so we can check we've done something
            $comops++;

            # we need to remove duplicate elements in the case where elements are nested between multiple matching elements
            %seen = ();
            @unique = ();
            foreach my $item (@elements) {
              push(@unique, $item) unless $seen{$item}++;
            }

            @elements = @unique;

            map { warn $_->as_HTML } @elements if DEBUG;
        }

        if ($comops) {
            $self->debug(
                'Added', scalar(@elements), ' elements to results'
            ) if DEBUG;

            push(@result, @elements);

            # update op counter for complete query to include ops performed
            # in this fragment
            $ops += $comops;
        }
        else {
            # looks like we got an empty comma section, e.g. : ",x, ,y,"
            # so we'll ignore it
        }

        last COMMA
            unless $query =~ / \G \s*,\s* /cgsx;
    }

    # check for any trailing text in the query that we couldn't parse
    if ($query =~ / \G (.+?) \s* $ /cgsx) {
        return $self->_report_error( $self->message( bad_spec => $1, $query ) );
    }

    # check that we performed at least one query operation
    unless ($ops) {
        return $self->_report_error( $self->message( bad_query => $query ) );
    }

    return wantarray
        ? @result
        : $self->new(@result);
}


sub list {
    return wantarray
        ?   @{ $_[0] }      # return list of items
        : [ @{ $_[0] } ];   # return unblessed list ref of items
}


sub size {
    return scalar @{ $_[0] };
}


sub first {
    my $self = shift;
    return @$self
        ? $self->[0]
        : $self->error_msg('is_empty');
}


sub last {
    my $self = shift;
    return @$self
        ? $self->[-1]
        : $self->error_msg('is_empty');
}


sub AUTOLOAD {
    my $self     = shift;
    my ($method) = ($AUTOLOAD =~ /([^:]+)$/ );
    return if $method eq 'DESTROY';

    # we allow Perl to catch any unknown methods that the user might
    # try to call against the HTML::Element objects in the query
    my @results =
        map  { $_->$method(@_) }
        @$self;

    return wantarray
        ?  @results
        : \@results;
}


1;

=head1 NAME

HTML::Query - jQuery-like selection queries for HTML::Element

=head1 SYNOPSIS

Creating an C<HTML::Query> object using the L<Query()|Query> constructor
subroutine:

    use HTML::Query 'Query';

    # using named parameters
    $q = Query( text  => $text  );          # HTML text
    $q = Query( file  => $file  );          # HTML file
    $q = Query( tree  => $tree  );          # HTML::Element object
    $q = Query( query => $query );          # HTML::Query object
    $q = Query(
        text  => $text1,                    # or any combination
        text  => $text2,                    # of the above
        file  => $file1,
        file  => $file2,
        tree  => $tree,
        query => $query,
    );

    # passing elements as positional arguments
    $q = Query( $tree );                    # HTML::Element object(s)
    $q = Query( $tree1, $tree2, $tree3, ... );

    # or from one or more existing queries
    $q = Query( $query1 );                  # HTML::Query object(s)
    $q = Query( $query1, $query2, $query3, ... );

    # or a mixture
    $q = Query( $tree1, $query1, $tree2, $query2 );

    # the final argument (in all cases) can be a selector
    my $spec = 'ul.menu li a';              # <ul class="menu">..<li>..<a>

    $q = Query( $tree, $spec );
    $q = Query( $query, $spec );
    $q = Query( $tree1, $tree2, $query1, $query2, $spec );
    $q = Query( text  => $text,  $spec );
    $q = Query( file  => $file,  $spec );
    $q = Query( tree  => $tree,  $spec );
    $q = Query( query => $query, $spec );
    $q = Query(
        text => $text,
        file => $file,
        # ...etc...
        $spec
    );

Or using the OO L<new()> constructor method (which the L<Query()|Query>
subroutine maps onto):

    use HTML::Query;

    $q = HTML::Query->new(
        # accepts the same arguments as Query()
    )

Or by monkey-patching a L<query()> method into L<HTML::Element|HTML::Element>.

    use HTML::Query 'query';                # note lower case 'q'
    use HTML::TreeBuilder;

    # build a tree
    my $tree = HTML::TreeBuilder->new;
    $tree->parse_file($filename);

    # call the query() method on any element
    my $query = $tree->query($spec);

Once you have a query, you can start selecting elements:

    @r = $q->query('a');            # all <a>...</a> elements
    @r = $q->query('a#menu');       # all <a> with "menu" id
    @r = $q->query('#menu');        # all elements with "menu" id
    @r = $q->query('a.menu');       # all <a> with "menu" class
    @r = $q->query('.menu');        # all elements with "menu" class
    @r = $q->query('a[href]');      # all <a> with 'href' attr
    @r = $q->query('a[href=foo]');  # all <a> with 'href="foo"' attr

    # you can specify elements within elements...
    @r = $q->query('ul.menu li a'); # <ul class="menu">...<li>...<a>

    # and use commas to delimit multiple path specs for different elements
    @r = $q->query('table tr td a, ul.menu li a, form input[type=submit]');

    # query() in scalar context returns a new query
    $r = $q->query('table');        # find all tables
    $s = $r->query('tr');           # find all rows in all those tables
    $t = $s->query('td');           # and all cells in those rows...

Inspecting query elements:

    # get number of elements in query
    my $size  = $q->size

    # get first/last element in query
    my $first = $q->first;
    my $last  = $q->last;

    # convert query to list or list ref of HTML::Element objects
    my $list = $q->list;            # list ref in scalar context
    my @list = $q->list;            # list in list context

All other methods are mapped onto the L<HTML::Element|HTML::Element> objects
in the query:

    print $query->as_trimmed_text;  # print trimmed text for each element
    print $query->as_HTML;          # print each element as HTML
    $query->delete;                 # call delete() on each element

=head1 DESCRIPTION

The C<HTML::Query> module is an add-on for the L<HTML::Tree|HTML::Tree> module
set. It provides a simple way to select one or more elements from a tree using
a query syntax inspired by jQuery. This selector syntax will be reassuringly
familiar to anyone who has ever written a CSS selector.

C<HTML::Query> is not an attempt to provide a complete (or even near-complete)
implementation of jQuery in Perl (see Ingy's L<pQuery|pQuery> module for a
more ambitious attempt at that). Rather, it borrows some of the tried and
tested selector syntax from jQuery (and CSS) that can easily be mapped onto
the C<look_down()> method provided by the L<HTML::Element|HTML::Element>
module.

=head2 Creating a Query

The easiest way to create a query is using the exportable L<Query()|Query>
subroutine.

    use HTML::Query 'Query';        # note capital 'Q'

It accepts a C<text> or C<file> named parameter and will create an
C<HTML::Query> object from the HTML source text or file, respectively.

    my $query = Query( text => $text );
    my $query = Query( file => $file );

This delegates to L<HTML::TreeBuilder|HTML::TreeBuilder> to parse the
HTML into a tree of L<HTML::Element|HTML::Element> objects.  The root
element returned is then wrapped in an C<HTML::Query> object.

If you already have one or more L<HTML::Element|HTML::Element> objects that
you want to query then you can pass them to the L<Query()|Query> subroutine as
arguments. For example, you can explicitly use
L<HTML::TreeBuilder|HTML::TreeBuilder> to parse an HTML document into a tree:

    use HTML::TreeBuilder;
    my $tree = HTML::TreeBuilder->new;
    $tree->parse_file($filename);

And then create an C<HTML::Query> object for the tree either using an
explicit C<tree> named parameter:

    my $query = Query( tree => $tree );

Or implicitly using positional arguments.

    my $query = Query( $tree );

If you want to query across multiple elements, then pass each one as a
positional argument.

    my $query = Query( $tree1, $tree2, $tree3 );

You can also create a new query from one or more existing queries,

    my $query = Query( query => $query );   # named parameter
    my $query = Query( $query1, $query2 );  # positional arguments.

You can mix and match these different parameters and positional arguments
to create a query across several different sources.

    $q = Query(
        text  => $text1,
        text  => $text2,
        file  => $file1,
        file  => $file2,
        tree  => $tree,
        query => $query,
    );

The L<Query()|Query> subroutine is a simple wrapper around the L<new()>
constructor method. You can instantiate your objects manually if you prefer.
The L<new()> method accepts the same arguments as for the L<Query()|Query>
subroutine (in fact, the L<Query()|Query> subroutine simply forwards all
arguments to the L<new()> method).

    use HTML::Query;

    my $query = HTML::Query->new(
        # same argument format as for Query()
    );

A final way to use C<HTML::Query> is to have it add a L<query()|query> method
to L<HTML::Element|HTML::Element>.  The C<query> import hook (all lower
case) can be specified to make this so.

    use HTML::Query 'query';                # note lower case 'q'
    use HTML::TreeBuilder;

    my $tree = HTML::TreeBuilder->new;
    $tree->parse_file($filename);

    # now all HTML::Elements have a query() method
    my @items = $tree->query('ul li');      # find all list items

This approach, often referred to as I<monkey-patching>, should be used
carefully and sparingly. It involves a violation of
L<HTML::Element|HTML::Element>'s namespace that could have unpredictable
results with a future version of the module (e.g. one which defines its own
C<query()> method that does something different). Treat it as something that
is great to get a quick job done right now, but probably not something to be
used in production code without careful consideration of the implications.

=head2 Selecting Elements

Having created an C<HTML::Query> object by one of the methods outlined above,
you can now fetch descendant elements in the tree using a simple query syntax.
For example, to fetch all the C<< E<lt>aE<gt> >> elements in the tree, you can
write:

    @links = $query->query('a');

Or, if you want the elements that have a specific C<class> attribute defined
with a value of, say C<menu>, you can write:

    @links = $query->query('a.menu');

More generally, you can look for the existence of any attribute and optionally
provide a specific value for it.

    @links = $query->query('a[href]');               # any href attribute
    @links = $query->query('a[href=index.html]');    # specific value

You can also find an element (or elements) by specifying an id.

    @links = $query->query('#menu');         # any element with id="menu"
    @links = $query->query('ul#menu');       # ul element with id="menu"

You can provide multiple selection criteria to find elements within elements
within elements, and so on.  For example, to find all links in a menu,
you can write:

    # matches: <ul class="menu"> <li> <a>
    @links = $query->query('ul.menu li a');

You can separate different criteria using commas.  For example, to fetch all
table rows and C<span> elements with a C<foo> class:

    @elems = $query->('table tr, span.foo');

=head2 Query Results

When called in list context, as shown in the examples above, the L<query()>
method returns a list of L<HTML::Element|HTML::Element> objects matching the
search criteria. In scalar context, the L<query()> method returns a new
C<HTML::Query> object containing the L<HTML::Element|HTML::Element> objects
found. You can then call the L<query()> method against that object to further
refine the query. The L<query()> method applies the selection to all elements
stored in the query.

    my $tables = $query->query('table');    # find all tables
    my $rows   = $tables->query('tr');      # find all rows in those tables
    my $cells  = $rows->query('td');        # find all cells in those rows

=head2 Inspection Methods

The L<size()> method returns the number of elements in the query. The
L<first()> and L<last()> methods return the first and last items in the
query, respectively.

    if ($query->size) {
        print "from ", $query->first->as_trimmed_text,
               " to ", $query->last->as_trimmed_text;
    }

If you want to extract the L<HTML::Element|HTML::Element> objects from the
query you can call the L<list()> method. This returns a list of
L<HTML::Element|HTML::Element> objects in list context, or a reference to a
list in scalar context.

    @elems = $query->list;
    $elems = $query->list;

=head2 Element Methods

Any other methods are automatically applied to each element in the list. For
example, to call the C<as_trimmed_text()> method on all the
L<HTML::Element|HTML::Element> objects in the query, you can write:

    print $query->as_trimmed_text;

In list context, this method returns a list of the return values from
calling the method on each element.  In scalar context it returns a
reference to a list of return values.

    @text_blocks = $query->as_trimmed_text;
    $text_blocks = $query->as_trimmed_text;

See L<HTML::Element|HTML::Element> for further information on the methods it
provides.

=head1 QUERY SYNTAX

=head2 Basic Selectors

=head3 element

Matches all elements of a particular type.

    @elems = $query->query('table');     # <table>

=head3 #id

Matches all elements with a specific id attribute.

    @elems = $query->query('#menu');     # <ANY id="menu">

This can be combined with an element type:

    @elems = $query->query('ul#menu');   # <ul id="menu">

=head3 .class

Matches all elements with a specific class attribute.

    @elems = $query->query('.info');     # <ANY class="info">

This can be combined with an element type and/or element id:

    @elems = $query->query('p.info');     # <p class="info">
    @elems = $query->query('p#foo.info'); # <p id="foo" class="info">
    @elems = $query->query('#foo.info');  # <ANY id="foo" class="info">

The selectors listed above can be combined in a whitespace delimited
sequence to select down through a hierarchy of elements.  Consider the
following table:

    <table class="search">
      <tr class="result">
        <td class="value">WE WANT THIS ELEMENT</td>
      </tr>
      <tr class="result">
        <td class="value">AND THIS ONE</td>
      </tr>
      ...etc..
    </table>

To locate the cells that we're interested in, we can write:

    @elems = $query->query('table.search tr.result td.value');

=head2 Attribute Selectors

W3C CSS 2 specification defines new constructs through which to select
based on specific attributes within elements. See the following link for the spec:
L<http://www.w3.org/TR/css3-selectors/#attribute-selectors>

=head3 [attr]

Matches elements that have the specified attribute, including any where
the attribute has no value.

    @elems = $query->query('[href]');     # <ANY href="...">

This can be combined with any of the above selectors.  For example:

    @elems = $query->query('a[href]');      # <a href="...">
    @elems = $query->query('a.menu[href]'); # <a class="menu" href="...">

You can specify multiple attribute selectors.  Only those elements that
match I<all> of them will be selected.

    @elems = $query->query('a[href][rel]'); # <a href="..." rel="...">

=head3 [attr=value]

Matches elements that have an attribute set to a specific value.  The
value can be quoted in either single or double quotes, or left unquoted.

    @elems = $query->query('[href=index.html]');
    @elems = $query->query('[href="index.html"]');
    @elems = $query->query("[href='index.html']");

You can specify multiple attribute selectors.  Only those elements that
match I<all> of them will be selected.

    @elems = $query->query('a[href=index.html][rel=home]');

=head3 [attr|=value]

Matches any element X whose foo attribute has a hyphen-separated list of
values beginning (from the left) with bar. The value can be quoted in either
single or double quotes, or left unquoted.

    @elems = $query->query('[lang|=en]');
    @elems = $query->query('p[class|="example"]');
    @elems = $query->query("img[alt|='fig']");

You can specify multiple attribute selectors.  Only those elements that
match I<all> of them will be selected.

    @elems = $query->query('p[class|="external"][lang|="en"]');

=head3 [attr~=value]

Matches any element X whose foo attribute value is a list of space-separated
values, one of which is exactly equal to bar. The value can be quoted in either
single or double quotes, or left unquoted.

    @elems = $query->query('[lang~=en]');
    @elems = $query->query('p[class~="example"]');
    @elems = $query->query("img[alt~='fig']");

You can specify multiple attribute selectors.  Only those elements that
match I<all> of them will be selected.

    @elems = $query->query('p[class~="external"][lang~="en"]');

KNOWN BUG: you can't have a C<]> character in the attribute value because
it confuses the query parser.  Fixing this is TODO.

=head2 Combinator Selectors

W3C CSS 2 specification defines new constructs through which to select
based on heirarchy with the DOM. See the following link for the spec:
L<http://www.w3.org/TR/css3-selectors/#combinators>

=head3 Immediate Descendents (children)

When you combine selectors with whitespace elements are selected if
they are descended from the parent in some way. But if you just want
to select the children (and not the grandchildren, great-grandchildren,
etc) then you can combine the selectors with the C<< > >> character.

 @elems = $query->query('a > img');

=head3 Non-Immediate Descendents

If you just want any descendents that aren't children then you can combine
selectors with the C<*> character.

 @elems = $query->query('div * a');

=head3 Immediate Siblings

If you want to use a sibling relationship then you can can join selectors
with the C<+> character.

 @elems = $query->query('img + span');

=head2 Combining Selectors

You can combine basic and hierarchical selectors into a single query

=head2 Combining Selectors

You can combine basic and hierarchical selectors into a single query
by separating each part with a comma.  The query will select all matching
elements for each of the comma-delimited selectors.  For example, to
find all C<a>, C<b> and C<i> elements in a tree:

    @elems = $query->query('a, b, i');

Each of these selectors can be arbitrarily complex.

    @elems = $query->query(
        'table.search[width=100%] tr.result[valign=top] td.value,
         form.search input[type=submit],
         a[href=index.html]'
    );

=head1 EXPORT HOOKS

=head2 Query

The C<Query()> constructor subroutine (note the capital letter) can be
exported as a convenient way to create C<HTML::Query> objects. It simply
forwards all arguments to the L<new()> constructor method.

    use HTML::Query 'Query';

    my $query = Query( file => $file, 'ul.menu li a' );

=head2 query

The C<query()> export hook can be called to monkey-patch a L<query()> method
into the L<HTML::Element|HTML::Element> module.

This is considered questionable behaviour in polite society which regards it
as a violation of the inner sanctity of the L<HTML::Element|HTML::Element>.

But if you're the kind of person that doesn't mind a bit of occasional
namespace abuse for the sake of getting the job done, then go right ahead.
Just don't blame me if it all blows up later.

    use HTML::Query 'query';                # note lower case 'q'
    use HTML::TreeBuilder;

    # build a tree
    my $tree = HTML::TreeBuilder->new;
    $tree->parse_file($filename);

    # call the query() method on any element
    my $query = $tree->query('ul li a');

=head1 METHODS

The C<HTML::Query> object is a subclass of L<Badger::Base|Badger::Base> and
inherits all of its method.

=head2 new(@elements,$selector)

This constructor method is used to create a new C<HTML::Query> object. It
expects a list of any number (including zero) of
L<HTML::Element|HTML::Element> or C<HTML::Query> objects.

    # single HTML::Element object
    my $query = HTML::Query->new($elem);

    # multiple element object
    my $query = HTML::Query->new($elem1, $elem2, $elem3, ...);

    # copy elements from an existing query
    my $query = HTML::Query->new($another_query);

    # copy elements from several queries
    my $query = HTML::Query->new($query1, $query2, $query3);

    # or a mixture
    my $query = HTML::Query->new($elem1, $query1, $elem2, $query3);

You can also use named parameters to specify an alternate source for a
element.

    $query = HTML::Query->new( file => $file );
    $query = HTML::Query->new( text => $text );

In this case, the L<HTML::TreeBuilder|HTML::TreeBuilder> module is used to
parse the source file or text into a tree of L<HTML::Element|HTML::Element>
objects.

For the sake of completeness, you can also specify element trees and queries
using named parameters:

    $query = HTML::Query->new( tree  => $tree );
    $query = HTML::Query->new( query => $query );

You can freely mix and match elements, queries and named sources.  The
query will be constructed as an aggregate across them all.

    $q = HTML::Query->new(
        text  => $text1,
        text  => $text2,
        file  => $file1,
        file  => $file2,
        tree  => $tree,
        query => $query1,
    );

The final, optional argument can be a selector specification.  This is
immediately passed to the L<query()> method which will return a new query
with only those elements selected.

    my $spec = 'ul.menu li a';              # <ul class="menu">..<li>..<a>

    my $query = HTML::Query->new( $tree, $spec );
    my $query = HTML::Query->new( text => $text, $spec );
    my $query = HTML::Query->new(
        text => $text,
        file => $file,
        $spec
    );

The list of arguments can also be passed by reference to a list.

    my $query = HTML::Query->new(\@args);

=head2 query($spec)

This method locates the descendant elements identified by the C<$spec>
argument for each element in the query. In list context it returns a list of
matching L<HTML::Element|HTML::Element> objects. In scalar context it returns
a new C<HTML::Query> object containing the element objects.

    my @elements  = $query->query($spec);
    my $new_query = $query->query($spec);

See L<"QUERY SYNTAX"> for the permitted syntax of the C<$spec> argument.

=head2 size()

Returns the number of elements in the query.

=head2 first()

Returns the first element in the query.

    my $elem = $query->first;

If the query is empty then an exception will be thrown. If you would rather
have an undefined value returned then you can use the C<try> method inherited
from L<Badger::Base|Badger::Base>. This effectively wraps the call to
C<first()> in an C<eval> block to catch any exceptions thrown.

    my $elem = $query->try('first') || warn "no first element\n";

=head2 last()

Similar to L<first()>, but returning the last element in the query.

    my $elem = $query->last;

=head2 list()

Returns a list of the L<HTML::Element|HTML::Element> object in the query in
list context, or a reference to a list in scalar context.

    my @elems = $query->list;
    my $elems = $query->list;

=head2 AUTOLOAD

The C<AUTOLOAD> method maps any other method calls to the
L<HTML::Element|HTML::Element> objects in the list. When called in list
context it returns a list of the values returned from calling the method on
each element. In scalar context it returns a reference to a list of return
values.

    my @text_blocks = $query->as_trimmed_text;
    my $text_blocks = $query->as_trimmed_text;

=head1 KNOWN BUGS

=head2 Attribute Values

It is not possible to use C<]> in an attribute value.  This is due to a
limitation in the parser which will be fixed RSN.

=head1 AUTHOR

Andy Wardley L<http://wardley.org>

=head1 MAINTAINER

Kevin Kamel <kamelkev@mailermailer.com>

=head1 CONTRIBUTORS

Vivek Khera <vivek@khera.org>
Michael Peters <wonko@cpan.org>

=head1 COPYRIGHT

Copyright (C) 2008 Andy Wardley.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<HTML::Tree|HTML::Tree>, L<HTML::Element|HTML::Element>,
L<HTML::TreeBuilder|HTML::TreeBuilder>, L<pQuery|pQuery>, L<http://jQuery.com/>

=cut

# Local Variables:
# mode: Perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
