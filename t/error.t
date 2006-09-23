#!perl

use lib qw(t) ;
use common ;

my $tests = [

	{
		name	=> 'unknown data type',
		opts	=> {},
		data	=> qr//,
		template => <<TMPL,
foo
TMPL
		expected => <<EXPECT,
bar
EXPECT
		error => qr/unknown template data/,
	},

	{
		name	=> 'missing include',
		skip	=> 0,
		data	=> {},
		template => '[%INCLUDE foo%]',
		error	=> qr/can't find/,
	},

	{
		name	=> 'code data',
		skip	=> 0,
		data	=> sub { return '' },
		template => 'bar',
		error	=> qr/data callback/,
	},


] ;

template_tester( $tests ) ;

exit ;

