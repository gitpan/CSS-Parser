# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..4\n"; }
END {print "not ok 1\n" unless $loaded;}
use CSS::Parser;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):


$tst = CSS::Parser->new or (print("not ok 2\n"), exit);
print "ok 2\n";

$tst->css_file("examples/test.css") or print "not ";
print "ok 3\n";

open(CSS,"examples/test.css") or die;
@css = <CSS>;
$css = join "",@css;
close CSS;
$tst->css_parse($css);
$tst->css_eof or print "not ";
print "ok 4\n";
