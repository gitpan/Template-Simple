package Template::Simple;

use warnings;
use strict;

use Carp ;
use Scalar::Util qw( reftype ) ;
use File::Slurp ;

use Data::Dumper ;

our $VERSION = '0.01';

my %opt_defaults = (

	pre_delim	=> qr/\[%/,
	post_delim	=> qr/%\]/,
	greedy_chunk	=> 0,
#	upper_case	=> 0,
#	lower_case	=> 0,
	include_paths	=> [ qw( templates ) ],
) ;

sub new {

	my( $class, %opts ) = @_ ;

	my $self = bless {}, $class ;

# get all the options or defaults into the object

	while( my( $name, $default ) = each %opt_defaults ) {

		$self->{$name} = defined( $opts{$name} ) ? 
				$opts{$name} : $default ;
	}

# make up the regexes to parse the markup from templates

# this matches scalar markups and grabs the name

	$self->{scalar_re} = qr{
		$self->{pre_delim}
		\s*			# optional leading whitespace
		(\w+?)			# grab scalar name
		\s*			# optional trailing whitespace
		$self->{post_delim}
	}xi ;				# case insensitive

#print "RE <$self->{scalar_re}>\n" ;

# this grabs the body of a chunk in either greedy or non-greedy modes

	my $chunk_body = $self->{greedy_chunk} ? qr/.+/s : qr/.+?/s ;

# this matches a marked chunk and grabs its name and text body

	$self->{chunk_re} = qr{
		$self->{pre_delim}
		\s*			# optional leading whitespace
		START			# required START token
		\s+			# required whitespace
		(\w+?)			# grab the chunk name
		\s*			# optional trailing whitespace
		$self->{post_delim}
		($chunk_body)		# grab the chunk body
		$self->{pre_delim}
		\s*			# optional leading whitespace
		END			# required END token
		\s+			# required whitespace
		\1			# match the grabbed chunk name
		\s*			# optional trailing whitespace
		$self->{post_delim}
	}xi ;				# case insensitive

#print "RE <$self->{chunk_re}>\n" ;

# this matches a include markup and grabs its template name

	$self->{include_re} = qr{
		$self->{pre_delim}
		\s*			# optional leading whitespace
		INCLUDE			# required INCLUDE token
		\s+			# required whitespace
		(\w+?)			# grab the included template name
		\s*			# optional trailing whitespace
		$self->{post_delim}
	}xi ;				# case insensitive

# load in any templates

	$self->add_templates( $opts{templates} ) ;

	return $self ;
}



sub render {

	my( $self, $template, $data ) = @_ ;

# make a copy if a scalar ref is passed as the template text is
# modified in place

	my $tmpl_ref = ref $template eq 'SCALAR' ? $template : \$template ;

	my $rendered = $self->_render_includes( $tmpl_ref ) ;

#print "INC EXP <$rendered>\n" ;

	$rendered = eval {
		 $self->_render_chunk( $rendered, $data ) ;
	} ;

	croak "Template::Simple $@" if $@ ;

	return $rendered ;
}

sub _render_includes {

	my( $self, $tmpl_ref ) = @_ ;

# make a copy of the initial template so we can render it.

	my $rendered = ${$tmpl_ref} ;

# loop until we can render no more include markups

	1 while $rendered =~
		 s{$self->{include_re}}
		    { ${ $self->_get_template($1) }
		  }e ;

	return \$rendered ;
}

my %renderers = (

	HASH	=> \&_render_hash,
	ARRAY	=> \&_render_array,
	CODE	=> \&_render_code,
# if no ref then data is a scalar so replace the template with just the data
	''	=> sub { \$_[2] },
) ;


sub _render_chunk {

	my( $self, $tmpl_ref, $data ) = @_ ;

#print "T ref [$tmpl_ref] [$$tmpl_ref]\n" ;
#print "CHUNK TMPL\n<$$tmpl_ref>\n" ;

#print Dumper $data ;

	return \'' unless defined $data ;

# now render this chunk based on the type of data

	my $renderer = $renderers{reftype $data || ''} ;

#print "EXP $renderer\nREF ", reftype $data, "\n" ;

	die "unknown template data type '$data'\n" unless defined $renderer ;

	return $self->$renderer( $tmpl_ref, $data ) ;
}

sub _render_hash {

	my( $self, $tmpl_ref, $href ) = @_ ;

	return $tmpl_ref unless keys %{$href} ;

# print "T ref [$tmpl_ref] [$$tmpl_ref]\n" ;
# print "HASH TMPL\n$$tmpl_ref\n" ;

# we need a local copy of the template to render

	my $rendered = ${$tmpl_ref} ;

# recursively render all top level chunks in this chunk

	$rendered =~ s{$self->{chunk_re}}
		      {
			# print "CHUNK $1\nBODY\n----\n<$2>\n\n------\n" ;
			${$self->_render_chunk( \$2, $href->{$1} ) }}gex ;

# now render scalars

#print "HASH TMPL\n<$rendered>\n" ;
#print Dumper $href ;

	$rendered =~ s{$self->{scalar_re}}
		      {
			#print "SCALAR $1 VAL $href->{$1}\n" ;
			 defined $href->{$1} ? $href->{$1} : '' }ge ;

#print "HASH2 TMPL\n$$rendered\n" ;

	return \$rendered ;
}

sub _render_array {

	my( $self, $tmpl_ref, $aref ) = @_ ;

# render this $tmpl_ref for each element of the aref and join them

	my $rendered ;

#print Dumper $aref ;

	$rendered .= ${$self->_render_chunk( $tmpl_ref, $_ )} for @{$aref} ;

	return \$rendered ;
}

sub _render_code {

	my( $self, $tmpl_ref, $cref ) = @_ ;

	my $rendered = $cref->( $tmpl_ref ) ;

	die <<DIE if ref $rendered ne 'SCALAR' ;
data callback to code didn't return a scalar or scalar reference
DIE

	return $rendered ;
}

sub add_templates {

	my( $self, $tmpls ) = @_ ;

#print Dumper $tmpls ;
	return unless defined $tmpls ;

 	ref $tmpls eq 'HASH' or croak "templates argument is not a hash ref" ;
	
	@{ $self->{templates}}{ keys %{$tmpls} } =
		map ref $_ eq 'SCALAR' ? \"${$_}" : \"$_", values %{$tmpls} ;

#print Dumper $self->{templates} ;

	return ;
}

sub delete_templates {

	my( $self, @names ) = @_ ;

	@names = keys %{$self->{templates}} unless @names ;

	delete @{$self->{templates}}{ @names } ;

	delete @{$self->{template_paths}}{ @names } ;

	return ;
}

sub _get_template {

	my( $self, $tmpl_name ) = @_ ;

#print "INC $tmpl_name\n" ;

	my $tmpls = $self->{templates} ;

# get the template from the cache and send it back if it was found there

	my $template = $tmpls->{ $tmpl_name } ;
	return $template if $template ;

# not found, so find, slurp in and cache the template

	$template = $self->_find_template( $tmpl_name ) ;
	$tmpls->{ $tmpl_name } = $template ;

	return $template ;
}

sub _find_template {

	my( $self, $tmpl_name ) = @_ ;

	foreach my $dir ( @{$self->{include_paths}} ) {

		my $tmpl_path = "$dir/$tmpl_name.tmpl" ;

#print "PATH: $tmpl_path\n" ;
		next unless -r $tmpl_path ;

# cache the path to this template

		$self->{template_paths}{$tmpl_name} = $tmpl_path ;

# slurp in the template file and return it as a scalar ref

		return scalar read_file( $tmpl_path, scalar_ref => 1 ) ;
	}

	die <<DIE ;
can't find template '$tmpl_name' in '@{$self->{include_paths}}'
DIE

}

1; # End of Template::Simple

__END__

=head1 NAME

Template::Simple - A simple and fast template module

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

    use Template::Simple;

    my $tmpl = Template::Simple->new();

    my $template = <<TMPL ;
[%INCLUDE header%]
[%START row%]
	[%first%] - [%second%]
[%END row%]
[%INCLUDE footer%]
TMPL

    my $data = {
	header_data	=> {
		date	=> 'Jan 1, 2008',
		author	=> 'Me, myself and I',
	},
	row	=> [
		{
			first	=> 'row 1 value 1',
			second	=> 'row 1 value 2',
		},
		{
			first	=> 'row 2 value 1',
			second	=> 'row 2 value 2',
		},
	],
	footer_data	=> {
		modified	=> 'Aug 31, 2006',
	},
    } ;

    my $rendered = $tmpl->render( $template, $data ) ;

=head1 DESCRIPTION

Template::Simple has these goals:

=over 4

=item * Support most common template operations

It can recursively include other templates, replace tokens (scalars),
recursively render nested chunks of text and render lists. By using
simple idioms you can get conditional renderings.

=item * Complete isolation of template from program code

This is very important as template design can be done by different
people than the program logic. It is rare that one person is well
skilled in both template design and also programming.

=item * Very simple template markup (only 4 markups)

The only markups are C<INCLUDE>, C<START>, C<END> and C<token>. See
MARKUP for more.

=item * Easy to follow rendering rules

Rendering of templates and chunks is driven from a data tree. The type
of the data element used in an rendering controls how the rendering
happens.  The data element can be a scalar or scalar reference or an
array, hash or code reference.

=item * Efficient template rendering

Rendering is very simple and uses Perl's regular expressions
efficiently. Because the markup is so simple less processing is needed
than many other templaters. Precompiling templates is not supported
yet but that optimization is on the TODO list.

=item * Easy user extensions

User code can be called during an rendering so you can do custom
renderings and plugins. Closures can be used so the code can have its
own private data for use in rendering its template chunk.

=back

=head2 new()

You create a Template::Simple by calling the class method new:

	my $tmpl = Template::Simple->new() ;

All the arguments to C<new()> are key/value options that change how
the object will do renderings.

=over 4

=item	pre_delim

This option sets the string or regex that is the starting delimiter
for all markups. You can use a plain string or a qr// but you need to
escape (with \Q or \) any regex metachars if you want them to be plain
chars. The default is qr/\[%/.

	my $tmpl = Template::Simple->new(
		pre_delim => '<%',
	);

	my $rendered = $tmpl->render( '<%FOO%]', 'bar' ) ;

=item	post_delim

This option sets the string or regex that is the ending delimiter
for all markups. You can use a plain string or a qr// but you need to
escape (with \Q or \) any regex metachars if you want them to be plain
chars. The default is qr/%]/.

	my $tmpl = Template::Simple->new(
		post_delim => '%>',
	);

	my $rendered = $tmpl->render( '[%FOO%>', 'bar' ) ;

=item	greedy_chunk

This boolean option will cause the regex that grabs a chunk of text
between the C<START/END> markups to become greedy (.+). The default is
a not-greedy grab of the chunk text. (UNTESTED)

=item	templates

This option lets you load templates directly into the cache of the
Template::Simple object. This cache will be searched by the C<INCLUDE>
markup which will be replaced by the template if found. The option
value is a hash reference which has template names (the name in the
C<INCLUDE> markup) for keys and their template text as their
values. You can delete or clear templates from the object cache with
the C<delete_template> method.


	my $tmpl = Template::Simple->new(
		templates	=> {

			foo	=> <<FOO,
[%baz%] is a [%quux%]
FOO
			bar	=> <<BAR,
[%user%] is not a [%fool%]
BAR
		},
	);

	my $template = <<TMPL ;
[%INCLUDE foo %]
TMPL

	my $rendered = $tmpl->render(
		$template,
		{
			baz => 'blue',
			quux => 'color,
		}
	) ;

=item	include_paths

Template::Simple can also load C<INCLUDE> templates from files. This
option lets you set the directory paths to search for those
files. Note that the template name in the C<INCLUDE> markup has the
.tmpl suffix appended to it when searched for in one of these
paths. The loaded file is cached inside the Template::Simple object
along with any loaded by the C<templates> option.

=back

=head1 METHODS

=head2 render

This method is passed a template and a data tree and it renders it and
returns a reference to the resulting string. The template argument can
be a scalar or a scalar reference. The data tree argument can be any
value allowed by Template::Simple when rendering a template. It can
also be a blessed reference (Perl object) since
C<Scalar::Util::reftype> is used instead of C<ref> to determine the
data type.

Note that the author recommends against passing in an object as this
breaks encapsulation and forces your object to be (most likely) a
hash. It would be better to create a simple method that copies the
object contents to a hash reference and pass that. But current
templaters allow passing in objects so that is supported here as well.

    my $rendered = $tmpl->render( $template, $data ) ;

=head2 add_templates

This method adds templates to the object cache. It takes a list of template names and texts just like the C<templates> constructor option.

	$tmpl->add_templates( 
		{
			foo	=> \$foo_template,
			bar	=> '[%include bar%]',
		}
	) ;

=head2 delete_templates

This method takes a list of template names and will delete them from
the template cache in the object. If you pass in an empty list then
all the templates will be deleted. This can be used when you know a
template file has been updated and you want to get it loaded back into
the cache. Note that you can delete templates that were loaded
directly (via the C<templates> constructor option or the
C<add_templates> method) or loaded from a file.

    # this deletes only the foo and bar templates from the object cache

	$tmpl->delete_templates( qw( foo bar ) ;

    # this deletes all of templates from the object cache

	$tmpl->delete_templates() ;

=head2 get_dependencies

This method render the only C<INCLUDE> markups of a template and it
returns a list of the file paths that were found and loaded. It is
meant to be used to build up a dependency list of included templates
for a main template. Typically this can be called from a script (see
TODO) that will do this for a set of main templates and will generate
Makefile dependencies for them. Then you can regenerate rendered
templates only when any of their included templates have changed. It
takes a single argument of a template.

UNKNOWN: will this require a clearing of the cache or will it do the
right thing on its own? or will it use the file path cache?

	my @dependencies =
		$tmpl->get_dependencies( '[%INCLUDE top_level%]' );

=head1 MARKUP

All the markups in Template::Simple use the same delimiters which are
C<[%> and C<%]>. You can change the delimiters with the C<pre_delim>
and C<post_delim> options in the C<new()> constructor.

=head2 Tokens

A token is a single markup with a C<\w+> Perl word inside. The token
can have optional whitespace before and after it. A token is replaced
by a value looked up in a hash with the token as the key. The hash
lookup keeps the same case as parsed from the token markup.

    [% foo %] [%BAR%]

Those will be replaced by C<$href->{foo}> and C<$href->{BAR}> assuming
C<$href> is the current data for this rendering. Tokens are only
parsed out during hash data rendering so see Hash Data for more.

=head2 Chunks

Chunks are regions of text in a template that are marked off with a
start and end markers with the same name. A chunk start marker is
C<[%START name%]> and the end marker for that chunk is C<[%END
name%]>. C<name> is a C<\w+> Perl word which is the name of this
chunk. The whitespace between C<START/END> and C<name> is required and
there is optional whitespace before C<START/END> and after the
C<name>. C<START/END> are case insensitive but the C<name>'s case is
kept. C<name> must match in the C<START/END> pair and it used as a key
in a hash data rendering. Chunks are the primary way to markup
templates for structures (sets of tokens), nesting (hashes of hashes),
repeats (array references) and callbacks to user code. Chunks are only
parsed out during hash data rendering so see Hash Data for more.

The body of text between the C<START/END> markups is grabbed with a
C<.+?> regular expression with the /s option enabled so it will match
all characters. By default it will be a non-greedy grab but you can
change that in the constructor by enabling the C<greedy_chunk> option.

    [%Start FOO%]
	[% START bar %]
		[% field %]
	[% end bar %]
    [%End FOO%]

=head2 Includes

=head1 RENDERING RULES

Template::Simple has a short list of rendering rules and they are easy
to understand. There are two types of renderings, include rendering
and chunk rendering. In the C<render> method, the template is an
unnamed top level chunk of text and it first gets its C<INCLUDE>
markups rendered. The text then undergoes a chunk rendering and a
scalar reference to that rendered template is returned to the caller.

=head2 Include Rendering

Include rendering is performed one time on a top level template. When
it is done the template is ready for chunk rendering.  Any markup of
the form C<[%INCLUDE name]%> will be replaced by the text found in the
template C<name>. The template name is looked up in the object's
template cache and if it is found there its text is used as the
replacement.

If a template is not found in the cache, it will be searched for in
the list of directories in the C<include_paths> option. The file name
will be a directory in that list appended with the template name and
the C<.tmpl> suffix. The first template file found will be read in and
stored in the cache. Its path is also saved and those will be returned
in the C<get_dependencies> method. See the C<add_templates> and
C<delete_templates> methods and the C<include_paths> option.

Rendered include text can contain more C<INCLUDE> markups and they
will also be rendered. The include rendering phase ends where there
are no more C<INCLUDE> found.

=head2 Chunk Rendering

A chunk is the text found between C<START> and C<END> markups and it
gets its named from the C<START> markup. The top level template is
considered an unamed chunk and also gets chunk rendered.

The data for a chunk determines how it will be rendered. The data can
be a scalar or scalar reference or an array, hash or code
reference. Since chunks can contain nested chunks, rendering will
recurse down the data tree as it renders the chunks.  Each of these
renderings are explained below. Also see the IDIOMS and BEST PRACTICES
section for examples and used of these renderings.

=head2 Scalar Data Rendering

If the current data for a chunk is a scalar or scalar reference, the
chunk's text in the templated is replaced by the scalar's value. This
can be used to overwrite one default section of text with from the
data tree.

=head2 Code Data Rendering

If the current data for a chunk is a code reference (also called
anonymous sub) then the code reference is called and it is passed a
scalar reference to the that chunk's text. The code must return a
scalar or a scalar reference and its value replaces the chunk's text
in the template. If the code returns any other type of data it is a
fatal error. Code rendering is how you can do custom renderings and
plugins. A key idiom is to use closures as the data in code renderings
and keep the required outside data in the closure.

=head2 Array Data Rendering

If the current data for a chunk is an array reference do a full chunk
rendering for each value in the array. It will replace the original
chunk text with the joined list of rendered chunks. This is how you do
repeated sections in Template::Simple and why there is no need for any
loop markups. Note that this means that rendering a chunk with $data
and [ $data ] will do the exact same thing. A value of an empty array
C<[]> will cause the chunk to be replaced by the empty string.

=head2 Hash Data Rendering

If the current data for a chunk is a hash reference then two phases of
rendering happen, nested chunk rendering and token rendering. First
nested chunks are parsed of of this chunk along with their names. Each
parsed out chunk is rendered based on the value in the current hash
with the nested chunk's name as the key.

If a value is not found (undefined), then the nested chunk is replaced
by the empty string. Otherwise the nested chunk is rendered according
to the type of its data (see chunk rendering) and it is replaced by
the rendered text.

Chunk name and token lookup in the hash data is case sensitive (see
the TODO for cased lookups).

Note that to keep a plain text chunk or to just have the all of its
markups (chunks and tokens) be deleted just pass in an empty hash
reference C<{}> as the data for the chunk. It will be rendered but all
markups will be replaced by the empty string.

=head2 Token Rendering

The second phase is token rendering. Markups of the form [%token%] are
replaced by the value of the hash element with the token as the
key. If a token's value is not defined it is replaced by the empty
string. This means if a token key is missing in the hash or its value
is undefined or its value is the empty string, the [%token%] markup
will be deleted in the rendering.

=head1 IDIOMS and BEST PRACTICES

With all template systems there are better ways to do things and
Template::Simple is no different. This section will show some ways to
handle typical template needs while using only the 4 markups in this
module. 

=head2 Conditionals

This conditional idiom can be when building a fresh data tree or
modifying an existing one.

	$href->{$chunk_name} = $keep_chunk ? {} : '' ;

If you are building a fresh data tree you can use this idiom to do a
conditional chunk:

	$href->{$chunk_name} = {} if $keep_chunk ;

To handle an if/else conditional use two chunks, with the else chunk's
name prefixed with NOT_ (or use any name munging you want). Then you
set the data for either the true chunk (just the plain name) or the
false trunk with the NOT_ name. You can use a different name for the
else chunk if you want but keeping the names of the if/else chunks
related is a good idea. Here are two ways to set the if/else data. The
first one uses the same data for both the if and else chunks and the
second one uses different data so the it uses the full if/else code
for that.

	$href->{ ($boolean ? '' : 'NOT_') . $chunk_name} = $data

	if ( $boolean ) {
		$href->{ $chunk_name} = $true_data ;
	else {
		$href->{ "NOT_$chunk_name" } = $false_data ;
	}

NOTE TO ALPHA USERS: i am also thinking that a non-existing key or
undefined hash value should leave the chunk as is. then you would need
to explicitly replace a chunk with the empty string if you wanted it
deleted.  It does affect the list of styles idiom. Any thoughts on
this change of behavior? Since this hasn't been released it is the
time to decide this.

=head2 Chunked Includes

One of the benefits of using include templates is the ability to share
and reuse existing work. But if an included template has a top level
named chunk, then that name would also be the same everywhere where
this template is included. If a template included another template in
multiple places, its data tree would use the same name for each and
not allow unique data to be rendered for each include. A better way is
to have the current template wrap an include markup in a named chunk
markup. Then the data tree could use unique names for each included
template. Here is how it would look:

	[%START foo_prime%][%INCLUDE foo%][%START foo_prime%]
	random noise
	[%START foo_second%][%INCLUDE foo%][%START foo_second%]

See the TODO section for some ideas on how to make this even more high level.

=head2 Repeated Sections

If you looked at the markup of Template::Simple you have noticed that
there is no loop or repeat construct. That is because there is no need
for one. Any chunk can be rendered in a loop just by having its
rendering data be an anonymous array. The renderer will loop over each
element of the array and do a fresh rendering of the chunk with this
data. A join (on '') of the list of renderings replaces the original
chunk and you have a repeated chunk.

=head2 A List of Mixed Styles

One formating style is to have a list of sections each which can have
its own style or content. Template::Simple can do this very easily
with just a 2 level nested chunk and an array of data for
rendering. The outer chunk includes (or contains) each of the desired
styles in any order. It looks like this:

	[%START para_styles%]
		[%START main_style%]
			[%INCLUDE para_style_main%]
		[%END main_style%]
		[%START sub_style%]
			[%INCLUDE para_style_sub%]
		[%END sub_style%]
		[%START footer_style%]
			[%INCLUDE para_style_footer%]
		[%END footer_style%]
	[%END para_styles%]

The other part to make this work is in the data tree. The data for
para_styles should be a list of hashes. Each hash contains the data
for one pargraph style which is keyed by the style's chunk name. Since
the other styles's chunk names are not hash they are deleted. Only the
style which has its name as a key in the hash is rendered. The data
tree would look something like this:

	[
		{
			main_style => $main_data,
		},
		{
			sub_style => $sub_data,
		},
		{
			sub_style => $other_sub_data,
		},
		{
			footer_style => $footer_data,
		},
	]

=head1 TESTS

The test scripts use a common test driver module in t/common.pl. It is
passed a list of hashes, each of which has the data for one test. A
test can create a ne Template::Simple object or use the one from the
previous test. The template source, the data tree and the expected
results are also important keys. See the test scripts for examples of
how to write tests using this common driver.

=over 4

=item name

This is the name of the test and is used by Test::More

=item opts

This is a hash ref of the options passed to the Template::Simple
constructor.  The object is not built if the C<keep_obj> key is set.

=item keep_obj

If set, this will make this test keep the Template::Simple object from
the previous test and not build a new one.

=item template

This is the template to render for this test. If not set, the test
driver will use the template from the previous test. This is useful to
run a series of test variants with the same template.

=item data

This is the data tree for the rendering of the template.

=item expected

This is the text that is expected after the rendering.

=item skip

If set, this test is skipped.

=back

=head1 TODO

Even though this template system is simple, that doesn't mean it can't
be extended in many ways. Here are some features and designs that
would be good extensions which add useful functionality without adding
too much complexity.

=head2 Compiled Templates

A commonly performed optimization in template modules is to precompile
(really preparse) templates into a internal form that will render
faster.  Precompiling is slower than rendering from the original
template which means you won't want to do it for each rendering. This
means it has a downside that you lose out when you want to render
using templates which change often. Template::Simple makes it very
easy to precompile as it already has the regexes to parse out the
markup. So instead of calling subs to do actual rendering, a
precompiler would call subs to generate a compiled rendering tree.
The rendering tree can then be run or processes with rendering data
passed to it. You can think of a precompiled template as having all
the nested chunks be replaced by nested code that does the same
rendering. It can still do the dynamic rendering of the data but it
saves the time of parsing the template souice. There are three
possible internal formats for the precompiled template:

=over 4

=item Source code

This precompiler will generate source code that can be stored and/or
eval'ed.  The eval'ed top level sub can then be called and passed the
rendering data.

=item Closure call tree

The internal format can be a nested set of closures. Each closure would contain
private data such as fixed text parts of the original template, lists
of other closures to run, etc. It is trivial to write a basic closure
generator which will make build this tree a simple task. 

=item Code ref call tree

This format is a Perl data tree where the nodes have a code reference
and its args (which can be nested instances of the same
nodes). Instead of executing this directly, you will need a small
interpreter to execute all the code refs as it runs through the tree.

This would make for a challenging project to any intermediate Perl
hacker. It just involves knowing recursion, data trees and code refs.
Contact me if you are interested in doing this.

=back

=head2 Cased Hash Lookups

One possible option is to allow hash renderings to always use upper or
lower cased keys in their lookups.

=head2 Render tokens before includes and chunks

Currently tokens are rendered after includes and chunks. If tokens
were rendered in a pass before the others, the include and chunk names
could be dynamically set. This would make it harder to precompile
templates as too much would be dynamic, i.e. you won't know what the
fixed text to parse out is since anything can be included at render
time. But the extra flexibility of changing the include and chunk
names would be interesting. It could be done easily and enabled by an
option.

=head2 Plugins

There are two different potential areas in Template::Simple that could
use plugins. The first is with the rendering of chunkas and
dispatching based on the data type. This dispatch table can easily be
replaced by loaded modules which offer a different way to
render. These include the precompiled renderers mentioned above. The
other area is with code references as the data type. By defining a
closure (or a closure making) API you can create different code refs
for the rendering data. The range of plugins is endless some of the
major template modules have noticed. One idea is to make a closure
which contains a different Template::Simple object than the current
one. This will allow rendering of a nested chunk with different rules
than the current chunk being rendered.

=head2 Data Escaping

Some templaters have options to properly escape data for some types of
text files such as html. this can be done with some variant of the
_render_hash routine which also does the scalar rendering (which is
where data is rendered). The rendering scalars code could be factored
out into a set of subs one of which is used based on any escaping
needs.

=head2 Data Tree is an Object

This is a concept I don't like but it was requested so it goes into
the TODO file. Currently C<render> can only be passed a regular
(unblessed) ref (or a scalar) for its data tree. Passing in an object
would break encapsulation and force the object layout to be a hash
tree that matches the layout of the template. I doubt that most
objects will want to be organized to match a template. I have two
ideas, one is that you add a method to that object that builds up a
proper (unblessed) data tree to pass to C<render>. The other is by
subclassing C<Template::Simple> and overriding C<render> with a sub
that does take an object hash and it can unbless it or build a proper
data tree and then call C<render> in SUPER::. A quick solution is to
use C<reftype> (from Scalar::Utils) instead of C<ref> to allow object
hashes to be passed in.

=head2 Includes and Closure Synergy

By pairing up an include template along with code that can generate
the appropriate data tree for its rendering, you can create a higher
level template framework (the synergy). Additional code can be
associated with them that will handle input processing and
verification for the templates (e.g. web forms) that need it. A key to
this will be making all the closures for the data tree. This can be
greatly simplified by using a closure maker sub that can create all
the required closures.

=head2 Metafields and UI Generation

Taking the synergy up to a much higher level is the concept of meta
knowledge of fields which can generate templates, output processing
(data tree generation), input processing, DB backing and more. If you
want to discuss such grandiose wacky application schemes in a long
rambling mind bending conversation, please contact me.

=head2 More Examples and Idioms

As I convert several scripts over to this module (they all used the
hack version), I will add them to an examples section or possibly put
them in another (pod only) module. Similarly the Idioms section needs
rendering and could be also put into a pod module. One goal requested
by an early alpha tester is to keep the primary docs as simple as the
markup itself. This means moving all the extra stuff (and plenty of
that) into other pod modules. All the pod modules would be in the same
cpan tarball so you get all the docs and examples when you install
this.

=head1 AUTHOR

Uri Guttman, C<< <uri at sysarch.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-template-simple at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Template-Simple>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Template::Simple

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Template-Simple>

=item * Search CPAN

L<http://search.cpan.org/dist/Template-Simple>

=back

=head1 ACKNOWLEDGEMENTS

I wish to thank Turbo10 for their support in developing this module.

=head1 COPYRIGHT & LICENSE

Copyright 2006 Uri Guttman, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut


find templates and tests

deep nesting tests

greedy tests

methods pod

delete_templates test

pod cleanup

fine edit

more tests

slurp dependency in makefile.pl

