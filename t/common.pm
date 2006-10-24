# common.pm - common test driver code

use Test::More ;
use Template::Simple ;

sub template_tester {

	my( $tests ) = @_ ;

# plan for one expected ok() call per test

	plan( tests => scalar @{$tests} ) ;

	my( $obj, $tmpl ) ;

# loop over all the tests

	foreach my $test ( @{$tests} ) {

		if ( $test->{skip} ) {
			ok( 1, "SKIPPING $test->{name}" ) ;
			next ;
		}

		unless( $obj && $test->{keep_obj} ) {

# if there is no kept object, we will constuct one

			$obj = eval {
				Template::Simple->new(
					%{ $test->{opts} || {} }
				) ;
			} ;

print $@ if $@ ;

# check for expected errors
# no errors in new() to catch (yet)

		}

		$test->{obj} = $obj ;

# see if we use the test's template or keep the previous one

		$tmpl = $test->{template} if defined $test->{template} ;

# run any setup sub before this test. this can is used to modify the
# object for this test (e.g. delete templates from the cache).

		if( my $pretest = $test->{pretest} ) {

			$pretest->($test) ;
		}

# get any existing template object

# render the template and catch any fatal errors

		my $rendered = eval {
			$obj->render( $tmpl, $test->{data} ) ;
		} ;

#print "ERR $@\n" if $@;

# if we had an error and expected it, we pass this test

		if ( $@ ) {

			if ( $test->{error} && $@ =~ /$test->{error}/ ) {

				ok( 1, $test->{name} ) ;
			}
			else {

				print "unexpected error: $@\n" ;
				ok( 0, $test->{name} ) ;
			}
			next ;
		}

# see if the expansion was what we expected

		my $ok = ${$rendered} eq $test->{expected} ;

# dump any bad expansions

		print <<ERR unless $ok ;
RENDERED
[${$rendered}]
EXPECTED
[$test->{expected}]
------
ERR

# report success/failure for this test

		ok( $ok, $test->{name} ) ;
	}
}

1 ;
