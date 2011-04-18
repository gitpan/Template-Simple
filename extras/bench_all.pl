#!/usr/bin/env perl

use strict;
use warnings;

use Template::Teeny;
use Template::Simple;
use Template::Teeny::Stash;
use Template;

my $iter = shift || -2 ;

use Benchmark qw(:hireswallclock cmpthese);
basic: {

    my $ts = Template::Simple->new() ;
	$ts->add_templates( { bench => 'hehe [% name %]' } ) ;

    my $tsc = Template::Simple->new() ;
	$tsc->add_templates( { bench => 'hehe [% name %]' } ) ;
	$tsc->compile( 'bench' ) ;

    my $tt = Template::Teeny->new({ include_path => ['t/tpl'] });
    my $stash = Template::Teeny::Stash->new({ name => 'bob' });

    my $t = Template->new({ INCLUDE_PATH => 't/tpl', COMPILE_EXT => '.tc' });
    my $out;
      open my $fh, '>/dev/null';

    $tt->process('bench.tpl', $stash, $fh);
    $t->process('bench.tpl', { name => 'bob' }, $fh);

    sub teeny {
        $tt->process('bench.tpl', $stash, $fh);
    }
    sub plain {
        $t->process('bench.tpl', { name => 'bob' }, $fh);    
    }

    sub simple {
        $ts->render('bench', { name => 'bob' } );    
    }

    sub ts_compiled {
        $tsc->render('bench', { name => 'bob' } );    
    }

    print "Very simple interpolation:\n";
    cmpthese( $iter, { teeny => \&teeny, template_toolkit => \&plain,
			simple => \&simple, ts_compiled => \&ts_compiled }) ;
}

some_looping_etc: {

my $tmpl = <<TMPL ;
<html>
  <head><title>[% title %]</title></head>
  <body>
    <ul>
      [% SECTION post %]
        <li>
            <h3>[% title %]</h3>
            <span>[% date %]</span>
        </li>
      [% END %]
    </ul>
  </body>
</html>
TMPL

    my $ts = Template::Simple->new() ;
	$ts->add_templates( { bench2 => $tmpl } ) ;

    my $tsc = Template::Simple->new() ;
	$tsc->add_templates( { bench2 => $tmpl } ) ;
	$tsc->compile( 'bench2' ) ;

    my $tt = Template::Teeny->new({ include_path => ['t/tpl'] });
    my $stash = Template::Teeny::Stash->new({ title => q{Bobs Blog} });

    my $post1 = Template::Teeny::Stash->new({ date => 'Today', title => 'hehe' });
    my $post2 = Template::Teeny::Stash->new({ date => '3 Days ago', title => 'Something new' });
    $stash->add_section('post', $post1);
    $stash->add_section('post', $post2);

    my $t = Template->new({ INCLUDE_PATH => 't/tpl', COMPILE_EXT => '.tc' });
    my $out;
     open my $fh, '>/dev/null';

    my $tt_vars = { 
        title => 'Bobs Blog', 
        posts => [
            { title => 'hehe', date => 'Today' },
            { date => '3 Days ago', title => 'Something new' },
        ],
    };
    teeny2();
   plain2();

    sub teeny2 {
        $tt->process('bench2-teeny.tpl', $stash, $fh);
    }
    sub plain2 {
        $t->process('bench2-tt.tpl', $tt_vars, $fh);    
    }

    sub simple2 {
        $ts->render('bench2', $tt_vars );    
    }

    sub ts_compiled2 {
        $tsc->render('bench2', $tt_vars );    
    }

    print "\nLoop and interpolation:\n";

    cmpthese( $iter, { teeny => \&teeny2, template_toolkit => \&plain2,
			simple => \&simple2, ts_compiled => \&ts_compiled2 }) ;

}




