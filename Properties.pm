package Scalar::Properties;

use warnings;
use strict;

our $VERSION = '0.12';

use overload
	q{""}  => \&value,
	bool   => \&is_true,
	'+'    => \&plus,
	'-'    => \&minus,
	'*'    => \&times,
	'/'    => \&divide,
	'%'    => \&modulo,
	'**'   => \&exp,
	'<=>'  => \&numcmp,
	'cmp'  => \&cmp,

	# the following would be autogenerated from 'cmp', but
	# we want to make the methods available explicitly, along
	# with case-insensitive versions

	'eq'   => \&eq,
	'ne'   => \&ne,
	'lt'   => \&lt,
	'gt'   => \&gt,
	'le'   => \&le,
	'ge'   => \&ge;

sub import {
	my $pkg = shift;
        my @defs = qw/integer float binary q qr/;
        my @req;
        @_ = ':all' unless @_;
        for my $key (@_) {
                if ($key eq ':all') {
                        @req = @defs;
                } else {
                        die __PACKAGE__." does not export '$key'"
                            unless grep /^$key$/ => @defs;
			push @req => $key;
                }
        }
	overload::constant map { $_ => \&handle } @req;

	# also manually export some routines

	my $callpkg = caller(1);
	no strict 'refs';
	*{"$callpkg\::$_"} = \&{"$pkg\::$_"} for
	    qw/pass_on passed_on get_pass_on/;
}

# object's hash keys that aren't properties (apart from those starting with
# and underscore, which are private anyway)

our %NON_PROPS = map { $_ => 1 } our @NON_PROPS =
    qw/true/;

# property propagation
sub pass_on     { our %PASS_ON = map { $_ => 1 } our @PASS_ON = @_ }
sub passed_on   { our %PASS_ON; exists $PASS_ON{+shift} }
sub get_pass_on { our @PASS_ON }

sub get_props {
	# get a list of the value's properties
	my $self = shift;
	our %NON_PROPS;
	return grep { !(/^_/ || exists $NON_PROPS{$_}) } keys %$self
}

sub del_prop {
	# delete one or more properties
	my $self = shift;
	our %NON_PROPS;
	for my $prop (@_) {
		die "$prop is private, not a property" if
		    substr($prop, 0, 1) eq '_';
		die "$prop cannot be deleted" if exists $NON_PROPS{$prop};
		delete $self->{$prop};
	}
}

sub del_all_props {
	my $self = shift;
	my @props = $self->get_props;
	delete $self->{$_} for @props;
}

sub handle {
	# create a new overloaded object
	my ($orig, $interp, $context, $sub, @prop) = @_;
	my $self = bless({
	    _value   => $orig,
	    _interp  => $interp,
	    _context => $context,
	    true    => ($orig) ? 1 : 0,
	}, __PACKAGE__);

	# propagate properties marked as such via pass_on from 
	# participating overloaded values passed in @prop

	for my $val (grep { ref $_ eq __PACKAGE__ } @prop) {
		for my $prop ($val->get_props) {
			$self->{$prop} = $val->{$prop} if passed_on($prop);
		}
	}

	return $self;
}

sub create {
	# take a value and a list of participating values and create
	# a new object from them by filling in the gaps that handle()
	# expects with defaults. As seen from handle(), the participating
	# values (i.e., the values that the first arg was derived from)
	# are passed so that properties can be properly propagated

	my ($val, @props) = @_;
	handle($val, $val, '', sub {}, @props);
}

# call this as a sub, not a method as it also takes unblessed scalars
# anything not of this package is stringified to give any potential
# other overloading a chance to get at it's actual value
sub value {
	# my $v = ref $_[0] eq __PACKAGE__ ? $_[0]->{_value} : "$_[0]";
	# $v =~ s/\\n/\n/gs;  # no idea why newlines become literal '\n'
	my $v = ref $_[0] eq __PACKAGE__ ? $_[0]->{_interp} : "$_[0]";
	return $v;
}

# ==================== Generated methods ====================
# Generate some string, numeric and boolean methods

sub gen_meth {
	my $template = shift;
	while (my ($name, $op) = splice(@_, 0, 2)) {
		(my $code = $template) =~ s/NAME/$name/g;
		$code =~ s/OP/$op/g;
		eval $code;
		die "Internal error: $@" if $@;
	}
}

my $binop = 'sub NAME {
    my($n, $m) = @_[0,1];
    ($m, $n) = ($n, $m) if($_[2]);
    create(value($n) OP value($m), $n, $m)
}';

gen_meth $binop, qw!
    plus     +
    minus    -
    times    *
    divide   /
    modulo   %
    exp      **
    numcmp   <=>
    cmp      cmp
    eq       eq
    ne       ne
    lt       lt
    gt       gt
    le       le
    ge       ge
    concat   .
    append   .
!;

# needs 'CORE::lc', otherwise 'Ambiguous call resolved as CORE::lc()'
my $bool_i = 'sub NAME {
    create( CORE::lc(value($_[0])) OP CORE::lc(value($_[1])), @_[0,1] )
}';

gen_meth $bool_i, qw!
    eqi      eq
    nei      ne
    lti      lt
    gti      gt
    lei      le
    gei      ge
!;

my $func = 'sub NAME {
    create(OP(value($_[0])), $_[0])
}';

gen_meth $func, qw!
    abs      abs
    length   CORE::length
    size     CORE::length
    uc       uc
    ucfirst  ucfirst
    lc       lc
    lcfirst  lcfirst
    hex      hex
    oct      oct
!;

# ==================== Miscellaneous Numeric methods ====================

sub zero   { create( $_[0] == 0, $_[0] ) }

# ==================== Miscellaneous Boolean methods ====================

sub is_true  {  $_[0]->{true} }
sub is_false { !$_[0]->{true} }

sub true {
	my $self = shift;
	$self->{true} = @_ ? shift : 1;
	return $self;
}

sub false { $_[0]->true(0) }

# ==================== Miscellaneous String methods ====================

sub reverse { create(scalar reverse(value($_[0])), $_[0]) };
sub swapcase { my $s = shift; $s =~ y/A-Za-z/a-zA-Z/; return create($s) }

# $foo->split(/PATTERN/, LIMIT)
sub split   {
	my ($orig, $pat, $limit) = @_;
	$limit ||= 0;
	$pat = qr/\s+/ unless ref($pat) eq 'Regexp';

	# The following should work:
	#   map { create($_, $orig) } split $pat => value($orig), $limit;
	# But there seems to be a bug in split
	# (cf. p5p: 'Bug report: split splits on wrong pattern')

	my @el;
	eval '@el = split $pat => value($orig), $limit;';
	die $@ if $@;
	return map { create($_, $orig) } @el;
}

# ==================== Code-execution methods ====================

sub times_do {
	my ($self, $sub) = @_;
	die 'times_do() method expected a coderef' unless ref $sub eq 'CODE';
	for my $i (1..$self) {
		$sub->($i)
	}
}

sub do_upto_step {
	my ($self, $limit, $step, $sub) = @_;
	die 'expected last arg to be a coderef'
	    unless ref $sub eq 'CODE';
	# for my $i ($self..$limit) { $sub->($i); }
	my $i = $self;
	while ($i <= $limit) {
		$sub->($i);
		$i += $step;
	}
}

sub do_downto_step {
	my ($self, $limit, $step, $sub) = @_;
	die 'expected last arg to be a coderef'
	    unless ref $sub eq 'CODE';
	my $i = $self;
	while ($i >= $limit) {
		$sub->($i);
		$i -= $step;
	}
}

sub do_upto   { do_upto_step  ($_[0], $_[1], 1, $_[2]) }
sub do_downto { do_downto_step($_[0], $_[1], 1, $_[2]) }

sub AUTOLOAD {
        my $self = shift;
        (my $prop = our $AUTOLOAD) =~ s/.*:://;
	return if $prop eq 'DESTROY' || substr($prop, 0, 1) eq '_';

	# $x->is_foo or $x->has_foo will return true if 'foo' is
	# a hash key with a true value

	return
	    defined $self->{ substr($prop, 4) } &&
		    $self->{ substr($prop, 4) } if
	    substr($prop, 0, 4) eq 'has_';

	return
	    defined $self->{ substr($prop, 3) } &&
		    $self->{ substr($prop, 3) } if
	    substr($prop, 0, 3) eq 'is_';

        if (@_) {
		$self->{$prop} = shift;
		return $self;
	}
	return $self->{$prop};
}

1;
__END__

=head1 NAME

Scalar::Properties - run-time properties on scalar variables

=head1 SYNOPSIS

  use Scalar::Properties;
  my $val = 0->true;
    if ($val && $val == 0) {
    print "yup, its true alright...\n";
  }

  my @text = (
    'hello world'->greeting(1),
    'forget it',
    'hi there'->greeting(1),
  );
  print grep { $_->is_greeting } @text;

  my $l =  'hello world'->length;

=head1 DESCRIPTION

Scalar::Properties attempts to make Perl more object-oriented by
taking an idea from Ruby: Everything you manipulate is an object,
and the results of those manipulations are objects themselves.

  'hello world'->length
  (-1234)->abs
  "oh my god, it's full of properties"->index('g')

The first example asks a string to calculate its length. The second
example asks a number to calculate its absolute value. And the
third example asks a string to find the index of the letter 'g'.

Using this module you can have run-time properties on initialized
scalar variables and literal values. The word 'properties' is used
in the Perl 6 sense: out-of-band data, little sticky notes that
are attached to the value. While attributes (as in Perl 5's attribute
pragma, and see the C<Attribute::*> family of modules) are handled
at compile-time, properties are handled at run-time.

Internally properties are implemented by making their values into
objects with overloaded operators. The actual properties are then
simply hash entries.

Most properties are simply notes you attach to the value, but some
may have deeper meaning. For example, the C<true> and C<false>
properties plays a role in boolean context, as the first example
of the Synopsis shows.

Properties can also be propagated between values. For details, see
the EXPORTS section below. Here is an example why this might be
desirable:

  pass_on('approximate');
  my $pi = 3->approximate(1);
  my $circ = 2 * $rad * $pi;

  # now $circ->approximate indicates that this value was derived
  # from approximate values

Please don't use properties whose name start with an underscore;
these are reserved for internal use.

You can set and query properties like this:

=over 4

=item C<$var-E<gt>myprop(1)>

sets the property to a true value. 

=item C<$var-E<gt>myprop(0)>

sets the property to a false value. Note that this doesn't delete
the property (to do so, use the C<del_props> method described
below).

=item C<$var-E<gt>is_myprop>, C<$var-E<gt>has_myprop>

returns a true value if the property is set (i.e., defined and has
a true value). The two alternate interfaces are provided to make
querying attributes sound more natural. For example:

  $foo->is_approximate;
  $bar->has_history;

=back

=head1 METHODS

Values thus made into objects also expose various utility methods.
All of those methods (unless noted otherwise) return the result as
an overloaded value ready to take properties and method calls
itself, and don't modify the original value.

=head2 INTROSPECTIVE METHODS

These methods help in managing a value's properties.

=over 4

=item C<$var->get_props>

Get a list of names of the value's properties.

=item C<$var->del_props(LIST)>

Deletes one or more properties from the value. This is different
than setting the property value to zero.

=item C<$var->del_all_props>

Deletes all of the value's properties.

=back

=head2 NUMERICAL METHODS

=over 4

=item C<plus(EXPR)>

Returns the value that is the sum of the value whose method has
been called and the argument value. This method also overloads
addition, so:

  $a = 7 + 2;
  $a = 7->plus(2);    # the same

=item C<minus(EXPR)>

Returns the value that is the the value whose method has been called
minus the argument value. This method also overloads subtraction.

=item C<times(EXPR)>

Returns the value that is the the value whose method has been called
times the argument value. This method also overloads multiplication.

=item C<divide(EXPR)>

Returns the value that is the the value whose method has been called
divided by the argument value. This method also overloads division.

=item C<modulo(EXPR)>

Returns the value that is the the value whose method has been called
modulo the argument value. This method also overloads the modulo
operator.

=item C<exp(EXPR)>

Returns the value that is the the value whose method has been called
powered by the argument value. This method also overloads the
exponentiation operator.

=item C<abs>

Returns the absolute of the value.

=item C<zero>

Returns a boolean value indicating whether the value is equal to 0.

=back

=head2 STRING METHODS

=over 4

=item C<length>, C<size>

Returns the result of the built-in C<length> function applied to
the value.

=item C<reverse>

Returns the reverse string of the value.

=item C<uc>, C<ucfirst>, C<lc>, C<lcfirst>, C<hex>, C<oct>

Return the result of the appropriate built-in function applied to
the value.

=item C<concat(EXPR)>, C<append(EXPR)>

Returns the result of the argument expression appended to the
value.

=item C<swapcase>

Returns a version of the value with every character's case reversed,
i.e. a lowercase character becomes uppercase and vice versa.

=item C<split /PATTERN/, LIMIT>

Returns a list of overloaded values that is the result of splitting
(according to the built-in C<split> function) the value along the
pattern, into a number of values up to the limit.

=back

=head2 BOOLEAN METHODS

=over 4

=item C<numcmp(EXPR)>

Returns the (overloaded) value of the numerical three-way comparison.
This method also overloads the C<E<lt>=E<gt>> operator.

=item C<cmp(EXPR)>

Returns the (overloaded) value of the alphabetical three-way
comparison.  This method also overloads the C<cmp> operator.

=item C<eq(EXPR)>, C<ne(EXPR)>, C<lt(EXPR)>, C<gt(EXPR)>, C<le(EXPR)>,
C<ge(EXPR)>

Return the (overlaoded) boolean value of the appropriate string
comparison. These methods also overload those operators.

=item C<eqi(EXPR)>, C<nei(EXPR)>, C<lti(EXPR)>, C<gti(EXPR)>,
C<lei(EXPR)>, C<gei(EXPR)>

These methods are case-insensitive versions of the above operators.

=item C<is_true>, C<is_false>

Returns the (overloaded) boolean status of the value.

=back

=head1 EXPORTS

Three subroutines dealing with how properties are propagated are
automatically exported. For an example of propagation, see the
DESCRIPTION section above.

=over 4

=item C<pass_on(LIST)>

Sets (replaces) the list of properties that are passed on. There
is only one such list for the whole mechanism. The whole property
interface is experimental, but this one in particular is likely to
change in the future.

=item C<passed_on(STRING)>

Tests whether a property is passed on and returns a boolean value.

=item C<get_pass_on>

Returns a list of names of properties that are passed on.

=back

=head1 BUGS

None known so far. If you find any bugs or oddities, please do inform the
authors.

=head1 AUTHORS

James A. Duncan <jduncan@fotango.com>

Marcel Grunauer, <marcel@codewerk.com>

Some contributions from David Cantrell, <david@cantrell.org.uk>

=head1 COPYRIGHT

Copyright 2001 Marcel Grunauer, James A. Duncan.
Portions copyright 2003 David Cantrell. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1), overload(3pm), Perl 6's properties.

=cut
