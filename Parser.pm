package CSS::Parser;

use strict;
require Exporter;
use vars qw($VERSION);
$VERSION = "0.05";

#use diagnostics;


sub new {
    my $class = shift;
    my $self = bless {
						'_case_sensitive' 	=> '0',
						'_buf'				=> ''
					}, $class;
    $self;
}

sub css_parse {
	my $self = shift;

	my $buf = \$self->{_buf};

	unless (defined $_[0]) {
		# on EOF, if there is something left then it is likely
		# that it should be a single line @rule
		# but just in case stylesheets become as poorly written
		# as some html pages are, we will test against that and flag
		# any remaining text as a comment if it isn't an @rule
		if (length $$buf) {

			my $at_rule;
			FINAL:{
				while (1) {
					#if it's only whitespace, then get rid of it
					if ($$buf =~ s/^\s$//s) {
						last FINAL;
					}
					#else if we've got the beginning of an at_rule
					elsif ($$buf =~ s/^\s*(\@.+?;)//s) {
						$at_rule = $1;
						while (1) {
							#the last ";" must not be within quotes, () or []
							#if it is then when need more
							if ($self->_quote($at_rule) || $self->_square($at_rule) || $self->_paren($at_rule)) {
								if ($$buf =~ s/^(.+?;)//s) {
									$at_rule .= $1;
									next;
								}
								#if there is no more, then flag it as comment
								else {
									$self->comment($at_rule);
									last FINAL;
								}
							}
							#if not in quotes..., then send them an at_rule
							else {
								#call to _prsrl, it'll take care of everything
							}
						}
					}
					#if it isn't an at_rule then I guess it's either bad css or a closing html comment
					else {
						$self->comment($$buf) if length $$buf;
						last FINAL;
					}
				}
			}
		}
		$$buf = '';
		return $self;
	}

	$$buf .= $_[0];

	TOKEN: {
		while (1) {
			#html comments
			if ($$buf =~ s/^\s*((?:<!--)|(?:-->))\$*//s) {
				$self->comment($1);
			}
			#the comments
			elsif ($$buf =~ m/^\s*\/\*/s) {
				#if we can eat up the whole comment, do so
				if ($$buf =~ s/\s*\/\*(.*?)(?<!\\)\*\///s) {
					$self->comment($1);
				}
				#else we need more
				else {
					$$buf = $1;
					last TOKEN;
				}
			}



			#deal with anything outside blocks and comments

			elsif ($$buf =~ s/^([^\{]+?)(?<!\\)(\{|\/\*)/$2/se) {
				my $txt = $1;

				while(1) {
				#if we stopped because of a comment, then trigger it so that we may get
				#it out of the way
					if ($2 eq "/*") {
						if ($$buf =~ s/^\/\*(.*?)\*\///s) {
							$self->comment($1);
							$$buf = $txt.$$buf;
							goto TOKEN;
						}
						#if we can't right now, wait for more data
						else {
							$$buf = $txt.$$buf;
							last TOKEN;
						}
					}
					else {
						#check to see that it isn't in quotes,...
						if ($self->_quote($txt) || $self->_square($txt) || $self->_paren($txt)) {
							if ($$buf =~ s/^(\{[^\{]+?)(?<!\\)(\{|\/\*)/$2/se) {
								$txt .= $1;
								next;
							}
							else {
								$$buf = $txt.$$buf;
								last TOKEN;
							}
						}
						else {
							goto RULE;
						}
					}
				}

				#now we're sure there isn't a comment around
				#it can either start with a single line at_rule (and contain several)
				#or not contain any as there can't be a sl at_rule between a "normal"
				#rule and the beggining of a block.
				RULE: {
					#Single line @rules (no block after it)
					if ($txt =~ s/^\s*(\@.+?;)//s) {
						my $at_rule;
						$at_rule = $1;
						while (1) {
							#the last ";" must not be within quotes...
							#if it is quoted then when need more from the current buffer
							if ($self->_quote($at_rule) || $self->_square($at_rule) || $self->_paren($at_rule)) {
								if ($$buf =~ s/^(.+?;)//s) {
									$at_rule .= $1;
									next;
								}
								#if there is no more, then we need more data
								else {
									$$buf = $at_rule.$txt.$$buf;
									last TOKEN;
								}
							}
							#if not in quotes..., then send them an at_rule
							else {
								#call to _prsrl, it'll take care of everything
								goto RULE;
							}
						}
					}
					#if it isn't a sl at_rule then it's either whitespace or another kind of rule
					else {
						if ($txt =~ s/^\s*?\{//s) {
							last RULE;
						}
						else {
							my $rules;
							#get rid of leading and trailing \s, of non single spaces, tabs and \n
							$txt =~ s/^\s*//s;
							$txt =~ s/(.*)\s*$//s;
							$rules = $1;
							$rules =~ s/ +|\n|\t/ /gs;

							#if we've got an at_rule
							if ($rules =~ s/^\s*(\@\w+)//) {
								$self->rule(["at_rule",$1]);
								last RULE;
							}

							#else if it's a list
							elsif ($rules =~ m/,/) {
								my @all_rules = split /,/,$rules;
								my @parsed = _prsrl(@all_rules);
								$self->rule(@parsed);
								last RULE;
							}

							#else if it's a hierarchy
							elsif ($rules =~ m/^\s*\w+(\s\w+)+/) {
								my @hierarchy = split / /,$rules;
								my @parsed = _prsrl(@hierarchy);
								$self->rule(["hierarchy",\@parsed]);
								last RULE;
							}

							#else it's a lonely rule
							else {
								last RULE if $rules =~ m/^\s*$/;
								my @parsed = _prsrl($rules);
								$self->rule(@parsed);
								last RULE;
							}
						}
					}
				}
			}

			#deal with blocks here
			elsif ($$buf =~ m/^\{/) {
				my $block;
				BLOCK: {
					while (1) {
						#if ($$buf =~ s/^(\{.*?)(?<!\\)(\}|\/\*)//s) {
						if ($$buf =~ s/^(.*?)(?<!\\)(\}|\/\*)//s) {
							$block .= $1;
							#if we stopped because of a comment, then trigger it so that we may get
							#it out of the way
							if ($2 eq "/*") {
								if ($$buf =~ s/^(.*?)(?<!\\)\*\///s) {
									$self->comment($1);
									$$buf = $block.$$buf;
									goto TOKEN;
								}
								#if we can't right now, wait for more data
								else {
									$$buf = $block.$$buf;
									last TOKEN;
								}
							}
							else {
								$block .= "}";
							}

							while (1) {

								#the closing "}" must not be within quotes
								#if it is quoted then when need more from the current buffer
								if ($self->_quote($block)) {
									if ($$buf =~ s/^(.*?)(?<!\\)(\}|\/\*)//s) {
										my $tmp_blk = $1;

										#then it can be a comment
										if ($2 eq "/*") {
											#but the comments must not be quoted
											#if it is quoted, then put it in the $block;
											if ($self->_quote($block.$tmp_blk)) {
												$block .= $tmp_blk."/*";
												next;
											}

											#otherwise we eat up the comment
											else {
												if ($$buf =~ s/^(.*?)(?<!\\)\*\///s) {
													$self->comment($1);
													$$buf = $block.$tmp_blk.$$buf;
													goto TOKEN;
												}
												#if we can't right now, wait for more data
												else {
													$$buf = $block.$tmp_blk."/*".$$buf;
													last TOKEN;
												}
											}
										}

										#if not a comment, we can add it to the lot and go round
										else {
											$block .= $tmp_blk."}";
											next;
										}
									}
									#if there is no more, then we need more data
									else {
										$$buf = $block.$$buf;
										last TOKEN;
									}
								}
								else {
									#here we need do the oblk count
									if ($self->_blk($block)) {
										$block =~ s/^\{(.*)\}\s*$/$1/s;
										my %props;
										my ($pr_n,$pr_v);
										while (1) {
											if ($block =~ m/^.*(?<!\\)\;/s) {
												$self->block($self->_propprs($block));
												$block = '';
											}
											else {
												my ($pr_n,$pr_v) = split /:/,$block;
												goto TOKEN if $pr_n =~ m/^\s*$/s;
												$pr_n =~ s/^\s*(\S.*\S)\s*$/$1/s;
												$pr_n =~ s/^\{\s*//;
												$pr_v =~ s/^\s*(\S.*\S)\s*$/$1/s;
												$props{$pr_n} = $pr_v;
												$self->block(\%props);
												goto TOKEN;
											}
										}
									goto TOKEN;
									}
									else {
										goto BLOCK;
									}
								}
							}
						}
						else {
							#we don't have enough data
							last TOKEN;
						}
					}
				}
			}

			else {
				#die "buf still contains $$buf";# if length $$buf;
				last TOKEN;
			}
		}
	}
}


sub _quote {
	#this sub checks the balance of quotes
	my $self = shift;
	my $str = shift;
	my $dbl = 0;
	my $sgl = 0;
	while ($str) {
		$str =~ s/^(?:\\\\|\\(?:\'|\")|[^\'\"])//s;
		last if !length $str;
		if ($str =~ s/^(?<!\\)\'//s && !$dbl) {
			$sgl = $sgl ? 0:1;
		}
		elsif ($str =~ s/^(?<!\\)\"//s && !$sgl) {
			$dbl = $dbl ? 0:1;
		}
	}
	if ($sgl || $dbl) {
		return 1;
	}
	else {
		return 0;
	}
}

sub _blk {
	#this sub checks the balance of braces
	my $self = shift;
	my $str = shift;
	my ($dbl,$sgl,$oblk);
	while ($str) {
		$str =~ s/^(?:\\\\|\\(?:\'|\"|\{|\})|[^\'\"\{\}]+?)//s;
		last if !length $str;
		if ($str =~ s/^\'//s && !$dbl) {
			$sgl = $sgl ? 0:1;
		}
		elsif ($str =~ s/^\"//s && !$sgl) {
			$dbl = $dbl ? 0:1;
		}
		elsif ($str =~ s/^\{//s && !$sgl && !$dbl) {
			$oblk++;
		}
		elsif ($str =~ s/^\}//s && !$sgl && !$dbl) {
			$oblk--;
		}
	}
	if ($oblk) {
		return 0;
	}
	else {
		return 1;
	}
}

sub _square {
	#this sub checks the balance of square braces
	my $self = shift;
	my $str = shift;
	my ($dbl,$sgl,$osq);
	while ($str) {
		$str =~ s/^(?:\\\\|\\(?:\'|\"|\[|\])|[^\'\"\[\]]+?)//s;
		last if !length $str;
		if ($str =~ s/^\'//s && !$dbl) {
			$sgl = $sgl ? 0:1;
		}
		elsif ($str =~ s/^\"//s && !$sgl) {
			$dbl = $dbl ? 0:1;
		}
		elsif ($str =~ s/^\[//s && !$sgl && !$dbl) {
			$osq++;
		}
		elsif ($str =~ s/^\]//s && !$sgl && !$dbl) {
			$osq--;
		}
	}
	if ($osq) {
		return 1;
	}
	else {
		return 0;
	}
}

sub _paren {
	#this sub checks the balance of square braces
	my $self = shift;
	my $str = shift;
	my ($dbl,$sgl,$opar);
	while ($str) {
		$str =~ s/^(?:\\\\|\\(?:\'|\"|\(|\))|[^\'\"\(\)]+?)//s;
		last if !length $str;
		if ($str =~ s/^\'//s && !$dbl) {
			$sgl = $sgl ? 0:1;
		}
		elsif ($str =~ s/^\"//s && !$sgl) {
			$dbl = $dbl ? 0:1;
		}
		elsif ($str =~ s/^\(//s && !$sgl && !$dbl) {
			$opar++;
		}
		elsif ($str =~ s/^\)//s && !$sgl && !$dbl) {
			$opar--;
		}
	}
	if ($opar) {
		return 1;
	}
	else {
		return 0;
	}
}

sub _propprs {
	my $self = shift;
	my $str = shift;
	my ($dbl,$sgl,$oblk);
	my $prop;
	my %props;
	while ($str) {
		$str =~ s/^(\\\\|\\(?:\'|\"|\{|\}|\;)|[^\'\"\{\}\;]+?)//s;
		last if !length $str;
		$prop .= $1;
		if ($str =~ s/^\'//s) {
			$sgl = $sgl ? 0:1 if !$dbl;
			$prop .= "'";
		}
		elsif ($str =~ s/^\"//s) {
			$dbl = $dbl ? 0:1 if !$sgl;
			$prop .= '"';
		}
		elsif ($str =~ s/^\{//s) {
			$oblk++ if (!$dbl && !$sgl);
			$prop .= '{';
		}
		elsif ($str =~ s/^\}//s) {
			$oblk-- if (!$dbl && !$sgl);
			$prop .= '}';
			if (!$oblk && !$dbl && !$sgl) {
				my ($pr_n,$pr_v) = split /\{/,$prop,2;
				$pr_n =~ s/^\s*//s;
				$pr_n =~ s/\s*$//s;
				$pr_v =~ s/^\s*//s;
				$pr_v =~ s/\s*$//s;
				$pr_v = "{".$pr_v;
				$props{$pr_n} = $pr_v;
				$prop = '';
			}
		}
		elsif ($str =~ s/^\;//s) {
			if (!$sgl && !$dbl && !$oblk) {
				my ($pr_n,$pr_v) = split /:/,$prop,2;
				if ($pr_n !~ m/^\s*$/s) {
					$pr_n =~ s/^\s*//s;
					$pr_n =~ s/\s*$//s;
					$pr_v =~ s/^\s*//s;
					$pr_v =~ s/\s*$//s;
					$props{$pr_n} = $pr_v;
				}
				$prop = '';
			}
			else {
				$prop .= ';';
			}
		}
		else {
			#$prop .= $1;
		}
	}
	return \%props;
}



sub _prsrl {

	my @parsable = @_;
	my @returned;
	my $rule;
	my ($el_n,$el_v);


	foreach $rule (@parsable) {
		my @tmp;

		next if $rule =~ m/^\s*$/;
		$rule =~ s/^\s*//s;
		$rule =~ s/\s*$//s;

		#it's a hierarchy...
		if ($rule =~ m/^\w+(\s\w+)+/s) {
			my @hierar = split / /,$rule;
			my @prs_hier = _prsrl(@hierar);
			@tmp = ("hierarchy",\@prs_hier);
			push @returned, \@tmp;
		}

		#id
		elsif ($rule =~ m/\#/) {
			($el_n,$el_v) = split /\#/, $rule;
			@tmp = ("id",$el_n,$el_v);
			push @returned, \@tmp;
		}

		#class
		elsif ($rule =~ /\./) {
			($el_n,$el_v) = split /\./, $rule;
			@tmp = ("class",$el_n,$el_v);
			push @returned, \@tmp;
		}

		#pseudo-class
		elsif ($rule =~ /\:/) {
			($el_n,$el_v) = split /:/, $rule;
			@tmp = ("pseudo-class",$el_n,$el_v);
			push @returned, \@tmp;
		}

		#element
		elsif ($rule =~ m/^\w+$/) {
			@tmp = ("element",$rule,"");
			push @returned, \@tmp;
		}

		#should not happen
		else {
			die "Bad rule was sent: $rule sent by " . (caller())[2] . "\n";
		}
	}
	return @returned;
}


sub css_eof {
    shift->css_parse(undef);
}


sub css_file {
    my($self, $file) = @_;
    no strict 'refs';
    local(*F);
    unless (ref($file) || $file =~ /^\*[\w:]+$/) {
		open(F, $file) or die "Can't open $file: $!";
		$file = \*F;
    }
    my $chunk = '';
    while(read($file, $chunk, 1024)) {
		$self->css_parse($chunk);
    }
    close($file);
    $self->css_eof;
}

sub case_sensitive {
	my $self = shift;
	@_ ? $self->{'_case_sensitive'} = shift :
		 $self->{'_case_sensitive'};
}




sub comment {
	#$comment
	#NB: comment also gets the <!-- and --> that are legal
	#within stylesheets
	#my $self = shift;
	#my $comment = shift;
}

sub rule {
	#( ($type,$elem_name,$elem_value),...)
	# or
	#( ($type=hierarchy,$list),...)
	#my $self = shift;
	#my @rul_elem = @_;
}

sub block {
	#\%properties
	#my $self = shift;
	#my %propt = %{$_[0]};
}
1;

__END__

=head1 NAME

CSS::Parser - Base class for CSS stylesheets parsing

=head1 SYNOPSIS

  C<package YourModule;>
  C<use CSS::Parser;>
  C<@ISA = qw(CSS::Parser);>

  C<sub block {>
	  C<my $self = shift;>
	  C<my %properties = %{$_[0]};>
  C<}>
  C<sub comment {>
	  C<my $self = shift;>
	  C<my $comment = shift;>
  C<}>
  C<sub rule {>
	C<my $self = shift;>
	C<my @rule_elem = @_;>
	C<#where:>
	C<#( ($type,$elem_name,$elem_value),...)>
	C<# or>
	C<#( ($type==hierarchy,$list),...)>
  C<}>

Then in a script:

  C<use YourModule;>
  C<my $css = new YourModule;>
  C<$css->css_parse(chunk1);>
  C<$css->css_parse(chunk2);>
  C<$css->css_eof>

  or

  C<$css->css_file(path/to/file.css or \*FHANDLE)>


B<NOTE>: the interface to rule will change in the coming version to become more useable


=head1 DESCRIPTION

C<CSS::Parser> will eat up CSS data and parsed chunks to callbacks. These callbacks have to be subclasses in order to get anything interesting out of the parser. The simplest subclass is one that would simply print out the CSS logical bits that have been found by the parser and info it has received about them. You should find an example of this called C<CSSPrinter> in the example dir of this distribution.

As of now, this parser isn't 100% CCS2 compliant, but it is very close to the CSS1 specification. That is to say that it should successfully parse about 99.9% of stylesheets that you are likely to find on the web, as no browser is yet fully CSS2 compliant either.

The next release (already seriously in the works as of this writing) will come very much closer to CSS2. Also, other modules will be provided together with this one so as to already implement the most useful subclasses. I am currently working on C<CSS::Expand> that given a stylesheet and an HTML page would return a page in which all tags will have their C<style> attribute set (a mechanism for a default stylesheet will be present) and C<CSS::Valid> that will reduce a stylesheet to its valid part as specified by the CSS2 specification.

These modules may become useful for example for robot writers who want to skip parts of pages that have a C<display: none> or a C<visibility: hide/hidden> style attribute set, so as to circumvent cheaters. An example of this will be included in the next release.

Also, as XML parsing will be done more and more in perl, and as CSS can be included in XML, it is likely that subclasses will be written to cooperate with modules in the XML:: hierarchy or with scripts using them.

=head1 METHODS

=head2 Public

B<new()>			The construstor, takes no parametres, returns the parser object.

B<css_parse()>	The main parsing method, takes a string for argument (C<$css->css_parse($string)>)

B<css_file()>		Parse a stylesheet from a file, take either a filename or a ref to a handle glob (C<$css->css_file("file.css")> or C<$css->css_file(\*CSS)>)

B<css_eof()>		Signals end of file to end parsing, no argument.

B<case_sensitive()>	Get/Set the case_sensitivity of returned rules. This may be useful for in CSS case-sensitivity depends on the case-sensitivity type of the document to which it is applied. That is, in HTML it will be case-insensitive whereas in XML it will not. (C<$css->case_sensitive(1)> or C<$case_s = $css->case_sensitive()>)

B<NOTE>: this doesn't do anything yet, it will be implemented at the same time as the new rule interface.

B<comment()>		Callback on comments. Receives a scalar containing the text of the comment without the /* and */.

B<rule()>		Callback on rules (both selectors and @rules). Contains a list of references to lists contain the following data for each rule met before a block C<$type> (class, id, at_rule, sl_at_rule, element, hierarchy, pseudo-clas). If it isn't a hierarchy then two other elements follow C<$name> (the name of the rule/selector eg: A for A:link) and C<$value> (the value of the rule/selector eg: link for A:link). If it is a hierarchy then there is only one element after type that is a reference to yet another list of lists as described above.

B<VERY IMPORTANT NOTE>: This is altogether I<too complicated, inappropriate and wrong>. I have found a much better way to express the complexity and variety of what rules/selectors can be, written it and am currently debugging it and finishing the last details. It should be out between mid and end of August with the next release of this module. Do not waste time building code based on this callback, the interface to come is everything but backwards compatible.

B<block()>	Callback on blocks. Receives a ref to a hash containing all the name/value pairs of the block's properties as keys/values.

B<NOTE>: This will remain very much as is, except that in the case of nested blocks the key will be the name before the nested block and the value a ref to a hash containing the property pairs.


B<NOTE>: These last three (or part of them) will probably gain a last parametre containing the original text.

=head2 Supposedly private

These are not supposed to be used outside, but you may find them useful (if not for use within this module, maybe for copying elsewhere, feel free). The return values are inverted between them, that is because it fits with their use within this module.

B<_blk()>			Returns 0 if the {} are uneven (escapes with \ and quoting are taken into account) and 1 if they are even.

B<_quote()>			Returns 1 if quoting is uneven (escapes with \ and quoting interquoting (eg "'" or '"') are taken into account) and 0 if even.

=head1 BUGS

Not too many though as it is undergoing change many are likely to appear. I have tested it succesfully on over 100 .css as of now, but they were fairly simple ones as are most on the web as of now.


=head1 CREDITS

The parsing strategy has been taken from Gisle Ass's L<HTML::Parser> modified as much as needed to do the job. The C<eof()> and C<css_file()> methods are very close to being verbatim copies of their C<HTML::Parser> equivalent.

=head1 AUTHOR

Robin Berjon, robin@idl-net.com

=head1 SEE ALSO

L<HTML::Parser>, the CSS2 specification (http://www.w3.org)

=head1 COPYRIGHT

Copyright (c) 1998 Robin Berjon. All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head2 DISCLAIMER

This module is alpha code, the interface for some functions I<will change soon>. It is only distributed so that users may have a look at what is in progress and make suggestions or offer bug fixes while in early stages of development. This module is B<NOT> useable for production as yet, use it at your own risk.

=cut
