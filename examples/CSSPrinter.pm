package CSSPrinter;
use strict;
use CSS::Parser;
use vars qw($VERSION @ISA);
$VERSION = $CSS::Parser::VERSION;
@ISA = qw(CSS::Parser);



sub comment {
	my $self = shift;
	my $comment = shift;
	print "Comment:\n";
	print "\t$comment";
	print "\n\n" . "-" x 80 . "\n\n";
}

sub rule {
	my $self = shift;
	my @rul_elem = @_;
	my ($rlm,$h_rlm,$lvl);

	print "Rule(s):\n";
	for $rlm (@rul_elem) {
		if ($$rlm[0] eq "hierarchy") {
			print "\thierarchy: \n";
			for $h_rlm (@{$$rlm[1]}) {
				print "\t\tlevel: ".$lvl++."\n";
				print "\t\ttype: $$h_rlm[0]\n";
				print "\t\tname: $$h_rlm[1]\n";
				print "\t\tvalue: $$h_rlm[2]\n\n";
			}
		}
		else {
			print "\ttype: $$rlm[0]\n";
			print "\tname: $$rlm[1]\n";
			print "\tvalue: $$rlm[2]\n\n";
		}
	}
	print "\n\n" . "-" x 80 . "\n\n";
}

sub block {
	my $self = shift;
	my %propt = %{$_[0]};
	my ($n,$v);
	print "Property(ies):\n";
	while ( ($n,$v) = each %propt) {
		print "\t$n: $v\n";
	}
	print "\n\n" . "-" x 80 . "\n\n";
}