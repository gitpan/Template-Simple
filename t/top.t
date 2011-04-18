#!perl

use lib qw(t) ;
use common ;

my $tests = [

	{
		name	=> 'top level - scalar data',
		data	=> 'bar',
		template => <<TEMPLATE,
junk
TEMPLATE
		expected => 'bar',
	},
	{
		name	=> 'top level - array data',
		data	=> [
			"foo\n",
			"bar\n",
		],
		template => <<TEMPLATE,
junk
TEMPLATE
		expected => <<EXPECTED,
foo
bar
EXPECTED
	},
	{
		name	=> 'top level - blessed array data',
		data	=> bless( [
			"foo\n",
			"bar\n",
		] ),
		template => <<TEMPLATE,
junk
TEMPLATE
		expected => <<EXPECTED,
foo
bar
EXPECTED
	},
	{
		name	=> 'top level - code data',
		compile_skip	=> 1,
		data	=> sub { \uc ${$_[0]} },
		template => <<TEMPLATE,
junk
TEMPLATE
		expected => <<EXPECTED,
JUNK
EXPECTED
	},
] ;

template_tester( $tests ) ;

exit ;

