package CSS::Parser;

use strict;
require 5.005;
use vars qw($VERSION);
$VERSION = '0.60';

# This parser deals simply with fairly loose CSS syntax.
# It doesn't know anything about what it is parsing, for that
# see other classes. This allows it to be the base for CSS::CSSn,
# CSS::STTSn and any other parser for a css-compatible syntax.

# The syntax it understands might not be very detailed, but it
# allows for a lot of future extensions. The existing derived
# classes are much stricter in what they accept.



# NOTES FOR ROBIN
#
# - this might be going to CPAN earlier than I thought...
# - start by building CSS1, then CSS2, then STTS3
# - if this moves to CPAN, then make it to CSS::Parser and so forth
#	and make this but a subclass
# - in Tessera, we will want to define extra rules, such as @tessera for instance
# - is there a way that a default sub (or any sub called by more than one callback)
#	may know how it was called (under what name ?)



# TO DO
# - document
# - commit to CPAN (after testing install on Linux)



sub new {
	my $class = shift;

	die "Uneven number of arguments for ${class}::new()" if scalar @_ % 2;
	# we could also check that given args are correct
	my %options = (
					style		=> 'callback',		# the parsing style (callback is the only one for the moment)
					handlers	=> {},
					@_
					);


	my @subs = qw(
					html_open_comment
					html_close_comment
					css_comment
					comment
					at_symbol
					at_rule
					selector_string
					block_start
					property
					value
					declaration
					block_end
					ruleset
					error
					default
				);




	# initialize the handlers here
	# the handler values are coderefs
	# the said subs must be able to act as methods,
	# that is they are called with the parser object as
	# their first argument. Some get a second argument (the token) others none because it's obvious
	for my $h (@subs) {
		no strict 'refs';
		if (defined $options{'handlers'}{$h}) {
			*{"$class::$h"} = \&{$options{'handlers'}{$h}};
		}
		elsif (defined $options{'handlers'}{'default'}) {
			*{"$class::$h"} = \&{$options{'handlers'}{'default'}};
			$options{'handlers'}{$h} = 1;
		}
		else {
			$options{'handlers'}{$h} = undef;
		}
	}


	my $self = \%options;
	return bless $self,$class;
}




# parse simply accepts the css text to be parsed as a ref
# and calls various callbacks
# Other parsing style may be added in the future
# but they will be backwards compatible
# Returns undef on error and 1 on success.
sub parse {
	my $self = shift;
	my $css = ${shift()};


	# enter the parse loop
	LOOP: {



		if ($self->shift_comment(\$css)) {
			# do nothing, it's just an alternative
		}

		elsif ($css =~ m/^\s*(?<!@)(?:[.:*[#a-zA-Z\200-\377]|\\[a-fA-F]{1,6}\s?|\\[ -~\200-\377])/s) {
			# we've got a selector string, parse the whole ruleset

			$css =~ s/^\s*((?:[^{]|\\{)+)//s;
			my $selector_string = $1;

			# we need to 'backtrack' for comments here.
			if ($selector_string =~ m{(?<!\\)\*/\s*$}s) {
				# we've got a comment at the end of the selector string
				$selector_string =~ s{(?<!\\)/\*(.*?)$}{}s;
				if ($self->{'handlers'}{'css_comment'}) {
					$self->css_comment("/* $1");
				}
				elsif ($self->{'handlers'}{'comment'}) {
					$self->comment("/* $1");
				}
			}

			if ($self->{'handlers'}{'selector_string'}) {
				$self->selector_string($selector_string);
			}



			# here we parse the block of the ruleset
			# we take property and value one at a time
			my $ruleset = $selector_string;
			my $decl_toggle = '';
			my $property;
			BLOCK: {
				redo BLOCK if $self->shift_comment(\$css);

				# block start '{'
				if ($css =~ s/^\s*(?<!\\){//s) {
					# block-start
					if ($self->{'handlers'}{'block_start'}) {
						$self->block_start;
					}
					$ruleset .= ' {';
				}


				# extract the declaration ($decl_toggle tells us where we are)
				elsif ($css =~ m/^\s*(?:[a-zA-Z\200-\377]|\\[a-fA-F]{1,6}\s?|\\[ -~\200-\377])/s) {

					# this is for the property
					if (!$decl_toggle) {

						$css =~ s/^\s*((?:[a-zA-Z\200-\377]|\\[a-fA-F]{1,6}\s?|\\[ -~\200-\377])(?:[a-zA-Z0-9\200-\377-]|\\[a-fA-F]{1,6}\s?|\\[ -~\200-\377])*)\s*//s;
						$property = $1;

						if ($self->{'handlers'}{'property'}) {
							$self->property($property);
						}

						COMMENT: {
							redo COMMENT if $self->shift_comment(\$css);
						}

						$css =~ s/^\s*://s;
						$ruleset .= "\n$property :";
						$decl_toggle = 'value';
					}

					# this is for the value
					else {

						$css =~ s/^\s*((?:[^;}]|\\;|\\})+)//s;
						my $value = $1;

						# we need to 'backtrack' for comments here.
						if ($value =~ m{(?<!\\)\*/\s*$}s) {
							# we've got a comment at the end
							$value =~ s{(?<!\\)/\*(.*?)$}{}s;
							if ($self->{'handlers'}{'css_comment'}) {
								$self->css_comment("/* $1");
							}
							elsif ($self->{'handlers'}{'comment'}) {
								$self->comment("/* $1");
							}
						}


						if ($self->{'handlers'}{'value'}) {
							$self->value($value);
						}
						if ($self->{'handlers'}{'declaration'}) {
							$self->declaration("$property : $value ;");
						}

						COMMENT: {
							redo COMMENT if $self->shift_comment(\$css);
						}

						$css =~ s/^\s*(?<!\\);//s;
						$ruleset .= " $value ;";
						$decl_toggle = '';
					}
				}

				# if there is no declaration left, we are at the end of the block
				# and may exit it
				elsif ($css =~ s/^\s*(?<!\\)}//s) {
					if ($self->{'handlers'}{'block_end'}) {
						$self->block_end;
					}
					$ruleset .= "\n}";
					last BLOCK;
				}

				# parse error
				else {
					if ($self->{'handlers'}{'error'}) {
						$self->error(\$css,'Unrecognized token within block');
					}
					return undef;
				}

				redo BLOCK;
			}
			# this is the end of the BLOCK loop, we have parsed the block now


			if ($self->{'handlers'}{'ruleset'}) {
				$self->ruleset($ruleset);
			}

		}


		elsif ($css =~ m/^\s*@(?:[a-zA-Z\200-\377]|\\[a-fA-F]{1,6}\s?|\\[ -~\200-\377])/s) {
			# at-rule

			$css =~ s/^\s*(@(?:[^;{]|\\;|\\{)+)//s;
			my $at_rule = $1;

			# we've got something that may contain comments, delete them
			if ($at_rule =~ m{(?<!\\)/\*}s) {
				my $tmp_at_rule;
				COMMENT: {
					last COMMENT if $at_rule =~ m/^\s*$/s;
					$at_rule =~ s{^(.*?)((?<!\\)/\*|<!--|-->)}{$2}es;
					$tmp_at_rule .= " $1";
					redo COMMENT if $self->shift_comment(\$at_rule);
				}
				$at_rule = $tmp_at_rule;
			}

			# at_rule, no block
			if ($css =~ s/^;//) {
				# it was an at_rule without a block
				if ($self->{'handlers'}{'at_rule'}) {
					$self->at_rule("$at_rule ;");
				}
			}

			# at_rule, a block
			elsif ($css =~ s/^{//) {

				if ($self->{'handlers'}{'at_symbol'}) {
					# at_symbol is different from at_rule
					# in that one expects a block to follow the former
					$self->at_symbol($at_rule);
				}

				# we've got a block start
				if ($self->{'handlers'}{'block_start'}) {
					$self->block_start;
				}

				# grab the next meaningful token to guess whether we have
				# a ruleset of just declarations
				# this is complicated by the need to eliminate comments
				my $nxt_toke;
				$css =~ m{^.*?(?<!\\)(;|{|}|/\*)}s;
				$nxt_toke = $1;

				# a comment occured before the first meaningful token
				# we must delete it before we look any further
				if ($nxt_toke eq '/*') {
					my $saved_css;
					COMMENT: {
						$css =~ s{^(.*?)(?<!\\)/\*}{/\*}s;
						$saved_css .= $1;
						$self->shift_comment(\$css);

						$css =~ m/^.*?(?<!\\)(;|{|}|\/\*)/s;
						$nxt_toke = $1;
						redo COMMENT if $nxt_toke eq '/*';
					}
					$css = $saved_css . $css;
				}


				# we're already at the end of the block
				# this doesn't mean that the block is empty, there could be
				# a solitary declaration with no ';' at the end
				if ($nxt_toke  eq '}') {

					# check for a solitary declaration (we know there is no comment)
					$css =~ s/^\s*(.*?)?(?<!\\)}//s;
					my $declaration = $1;

					# there is indeed something (and there can be only one)
					if ($declaration) {
						my ($property,$value) = split /:/, $declaration, 2;

						if ($self->{'handlers'}{'property'}) {
							$self->property($property);
						}

						if ($self->{'handlers'}{'value'}) {
							$self->value($value);
						}

						if ($self->{'handlers'}{'declaration'}) {
							$self->declaration("$property : $value ;");
						}

					}


					if ($self->{'handlers'}{'block_end'}) {
						$self->block_end;
					}
				}

				# if it is a ruleset, we pass the control back to the main loop
				# the latter will parse the ruleset(s) and catch the block_end
				# which indicates that the at_rule is over
				# this even allows for nested at_rules
				elsif ($nxt_toke  eq '{') {
					# nothing happens here
				}

				# if it is just declarations, we parse them (this is code duplication,
				# but never mind, we'll fix that later (esp. as we'll need code that
				# can parse declarations on their own within a style="" attr))
				elsif ($nxt_toke  eq ';') {

					my $decl_toggle = '';
					my $property = '';
					DECLARATION:{

						redo DECLARATION if $self->shift_comment(\$css);

						# extract the declaration ($decl_toggle tells us where we are)
						if ($css =~ m/^\s*(?:[a-zA-Z\200-\377]|\\[a-fA-F]{1,6}\s?|\\[ -~\200-\377])/s) {

							# this is for the property
							if (!$decl_toggle) {

								$css =~ s/^\s*((?:[a-zA-Z\200-\377]|\\[a-fA-F]{1,6}\s?|\\[ -~\200-\377])(?:[a-zA-Z0-9\200-\377-]|\\[a-fA-F]{1,6}\s?|\\[ -~\200-\377])*)\s*//s;
								$property = $1;

								if ($self->{'handlers'}{'property'}) {
									$self->property($property);
								}

								COMMENT: {
									redo COMMENT if $self->shift_comment(\$css);
								}

								$css =~ s/^\s*://s;
								$decl_toggle = 'value';
							}

							# this is for the value
							else {

								$css =~ s/^\s*((?:[^;}]|\\;|\\})+)//s;
								my $value = $1;

								# we need to 'backtrack' for comments here.
								if ($value =~ m{(?<!\\)\*/\s*$}s) {
									# we've got a comment at the end
									$value =~ s{(?<!\\)/\*(.*?)$}{}s;
									if ($self->{'handlers'}{'css_comment'}) {
										$self->css_comment("/* $1");
									}
									elsif ($self->{'handlers'}{'comment'}) {
										$self->comment("/* $1");
									}
								}


								if ($self->{'handlers'}{'value'}) {
									$self->value($value);
								}
								if ($self->{'handlers'}{'declaration'}) {
									$self->declaration("$property : $value ;");
								}

								COMMENT: {
									redo COMMENT if $self->shift_comment(\$css);
								}

								$css =~ s/^\s*(?<!\\);//s;
								$decl_toggle = '';
							}
						}

						# if there is no declaration left, we are at the end of the block
						# and may exit it
						elsif ($css =~ s/^\s*}//s) {
							if ($self->{'handlers'}{'block_end'}) {
								$self->block_end;
							}
							last DECLARATION ;
						}

						# parse error
						else {
							if ($self->{'handlers'}{'error'}) {
								$self->error(\$css,'Token not recognized as declaration');
							}
							return undef;
						}

						redo DECLARATION;
					}
				}

				# error
				else {
					# call the error callback if it exists
					# and return undef
					if ($self->{'handlers'}{'error'}) {
						$self->error(\$css,'At-rule content not recognized');
					}
					return undef;
				}
			}

			# error, this souldn't happen
			else {
				# call the error callback if it exists
				# and return undef
				if ($self->{'handlers'}{'error'}) {
					$self->error(\$css,'Unknown token, thought it was at-rule but appears to be wrong');
				}
				return undef;
			}
		}

		# we're meeting a solitary end-of-block, we probably just parsed a ruleset
		# nested within an at-rule
		elsif ($css =~ s/^\s*(?<!\\)}//s) {
			if ($self->{'handlers'}{'block_end'}) {
				$self->block_end;
			}
		}

		# we-ve reached eof/eos
		# exit the parse stating that it was successful
		elsif ($css =~ s/^\s*$//s) {
			return 1;
		}


		# syntax error
		# do something with the error if appropriate, and return undef to signal failure
		else {
			if ($self->{'handlers'}{'error'}) {
				$self->error(\$css,'Unknown token');
			}
			return undef;
		}

		redo LOOP;

		# end of the parse loop
	}
}




# deletes the three kinds of comments
# accepts a reference to the $css text
# return true upon succes, undef otherwise
sub shift_comment {
	my $self = shift;
	my $css = shift;
	if ($$css =~ s/^\s*<!--//s) {
		# html open comment

		if ($self->{'handlers'}{'html_open_comment'}) {
			$self->html_open_comment;
		}
		elsif ($self->{'handlers'}{'comment'}) {
			$self->comment('<!--');
		}
		return 1;
	}
	elsif ($$css  =~ s/^\s*-->//s) {
		# html close comment

		if ($self->{'handlers'}{'html_close_comment'}) {
			$self->html_close_comment;
		}
		elsif ($self->{'handlers'}{'comment'}) {
			$self->comment('-->');
		}
		return 1;
	}
	elsif ($$css  =~ s{^\s*(?<!\\)/\*}{}s) {
		# css comment
		# return it's content

		$$css=~ s{(.*?)(?<!\\)\*/}{}sm;
		my $css_comment = $1;

		if ($self->{'handlers'}{'css_comment'}) {
			$self->css_comment("/* $css_comment */");
		}
		elsif ($self->{'handlers'}{'comment'}) {
			$self->comment("/* $css_comment */");
		}
		return 1;
	}
	return undef;
}



1;

__END__


=head1 NAME

CSS::Parser - parser for CSS-style syntax

=head1 SYNOPSIS

 use CSS::Parser;

 my $css = CSS::Parser->new(
                           handlers => {
                                        css_comment      => \&css_com,
                                        selector_string  => \&sel,
                                        block_start      => \&blk_s,
                                        property         => \&prop,
                                        value            => \&val,
                                        block_end        => \&blk_e,
                                        at_rule          => \&atr,
                                        at_symbol        => \&ats,
                                        error            => \&error
                                        }
                           );

 $css->parse(\$some_css_text);

 sub css_com {
    my $self = shift;
    my $comment = shift;
    print "css comment:\n\t$comment\n";
 }

 ...

=head1 DESCRIPTION

The C<CSS::Parser> deals simply with fairly loose CSS syntax.
It doesn't know anything about what it is parsing, for that
see other classes. This allows it to be the base for C<CSS::CSSn>,
C<CSS::STTSn> and any other parser for a css-compatible syntax.

Chances are, you will want to use one of the existing subclasses or
to subclass it yourself.

The interface to C<CSS::Parser> is:

=over 4

=item my $css = CSS::Parser->new([style => $parse_style],[handlers => $hashref_of_handlers]);

The constructor takes a variety of options provided in a hash.

I<style> defines the style of parsing that you want from the parser. As
of now the only style is 'callback' (default), however this may evolve
in the future.

I<handlers> specifies a hash of callbacks to be called when a given
token has been met. Callbacks are CODEREFS. The callback sub will
receive the parser object as it's first argument, and optionally the
token when it makes sense (eg: selector_string will be passed the
selector, but block_start won't receive the '{').

One may use 'default' to activate them all. Note that you can set a
callback to the empty string (not undef) if you wish to set a default
for all but to deactivate that specific callback.

=over 8

=item * html_open_comment

Called when a <!-- comment is seens, no second argument.

=item * html_close_comment

Called when a --> comment is seens, no second argument.

=item * css_comment

Called when a css comment of the form /* text */ is seen. Receives the
comment with leading /* and trailing */.

=item * comment

Called when any of the above types of comment is seen. Receives the
comment as is.

=item * at_symbol

Called when an at-symbol (@ident) is seen and is followed by a block.
The block is parsed subsequently. Receives the at-symbol.

=item * at_rule

Called when a block-less at-rule (@import url('foo') print;) is seen,
receives the entire rule (it isn't further tokenized, that is the job
of the subclass because it requires it to know what is expected after
the specific at-keyword).

=item * selector_string

Called whenever a selector string is seen and receives the entire
string as tokenising it further would require knowledge of the specific
variant of CSS.

=item * block_start

Called when the beginning of a block is seen ({), receives nothing.

=item * property

Called when a property is seen, receives the property.

=item * value

Called when a value is seen, receives the value which is not parsed to
know it's individual components, that belongs to the subclass.

=item * declaration

Called with property : $value ;

=item * block_end

Same as block_start, for }.

=item * ruleset

Called with selector_string '{' [declaration;]* '}'

=item * error

Called whenever the parser notices an error, receives what is left of
the CSS text when the error occurred plus an informative message.

=item * default

The use for default is to substitute a standard callback for all
callbacks that are not defined.

=back


=item $css->parse( $string_ref );

Tells the parser to go ahead and parse the provided reference to a
string. Note that the string will be empty after the parser has
finished, unless the stylesheet contains an error. It returns 1 upon
success and undef upon failure.

=back


=head1 SEE ALSO

L<XML::Parser>, L<HTML::Parser>, L<HTML::TreeBuilder>

=head1 COPYRIGHT

Copyright 1998-1999 Robin Berjon (robin@knowscape.com). All rights
reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut


