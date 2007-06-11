#line 1 "Moose/Meta/Method/Accessor.pm"

package Moose::Meta::Method::Accessor;

use strict;
use warnings;

use Carp 'confess';

our $VERSION   = '0.03';
our $AUTHORITY = 'cpan:STEVAN';

use base 'Moose::Meta::Method',
         'Class::MOP::Method::Accessor';

## Inline method generators

sub generate_accessor_method_inline {
    my $self      = $_[0];
    my $attr      = $self->associated_attribute; 
    my $attr_name = $attr->name;

    my $value_name = $attr->should_coerce ? '$val' : '$_[1]';
	my $mi = $attr->associated_class->get_meta_instance;
	my $slot_name = sprintf "'%s'", $attr->slots;
	my $inv = '$_[0]';
    my $code = 'sub { '
    . $self->_inline_pre_body(@_)
    . 'if (scalar(@_) == 2) {'
        . $self->_inline_check_required
        . $self->_inline_check_coercion
        . $self->_inline_check_constraint($value_name)
		. $self->_inline_store($inv, $value_name)
		. $self->_inline_trigger($inv, $value_name)
    . ' }'
    . $self->_inline_check_lazy
    . $self->_inline_post_body(@_)
    . 'return ' . $self->_inline_auto_deref($self->_inline_get($inv))
    . ' }';
    
    # NOTE:
    # set up the environment
    my $type_constraint = $attr->type_constraint 
                                ? $attr->type_constraint->_compiled_type_constraint
                                : undef;
    
    my $sub = eval $code;
    confess "Could not create accessor for '$attr_name' because $@ \n code: $code" if $@;
    return $sub;    
}

sub generate_writer_method_inline {
    my $self      = $_[0];
    my $attr      = $self->associated_attribute; 
    my $attr_name = $attr->name;
    
    my $value_name = $attr->should_coerce ? '$val' : '$_[1]';
	my $inv = '$_[0]';
    my $code = 'sub { '
    . $self->_inline_pre_body(@_)
    . $self->_inline_check_required
    . $self->_inline_check_coercion
	. $self->_inline_check_constraint($value_name)
	. $self->_inline_store($inv, $value_name)
	. $self->_inline_post_body(@_)
	. $self->_inline_trigger($inv, $value_name)
    . ' }';
    
    # NOTE:
    # set up the environment
    my $type_constraint = $attr->type_constraint 
                                ? $attr->type_constraint->_compiled_type_constraint
                                : undef;    
    
    my $sub = eval $code;
    confess "Could not create writer for '$attr_name' because $@ \n code: $code" if $@;
    return $sub;    
}

sub generate_reader_method_inline {
    my $self      = $_[0];
    my $attr      = $self->associated_attribute; 
    my $attr_name = $attr->name;
    
    my $code = 'sub {'
    . $self->_inline_pre_body(@_)
    . 'confess "Cannot assign a value to a read-only accessor" if @_ > 1;'
    . $self->_inline_check_lazy
    . $self->_inline_post_body(@_)
    . 'return ' . $self->_inline_auto_deref( '$_[0]->{$attr_name}' ) . ';'
    . '}';
    
    # NOTE:
    # set up the environment
    my $type_constraint = $attr->type_constraint 
                                ? $attr->type_constraint->_compiled_type_constraint
                                : undef;    
    
    my $sub = eval $code;
    confess "Could not create reader for '$attr_name' because $@ \n code: $code" if $@;
    return $sub;
}

*generate_reader_method   = \&generate_reader_method_inline;
*generate_writer_method   = \&generate_writer_method_inline;
*generate_accessor_method = \&generate_accessor_method_inline;

sub _inline_pre_body { '' }
sub _inline_post_body { '' }

sub _inline_check_constraint {
	my ($self, $value) = @_;
	
	my $attr = $self->associated_attribute; 
	
	return '' unless $attr->has_type_constraint;
	
	return sprintf <<'EOF', $value, $value, $value, $value
defined($type_constraint->(%s))
	|| confess "Attribute (" . $attr->name . ") does not pass the type constraint ("
       . $attr->type_constraint->name . ") with " . (defined(%s) ? "'%s'" : "undef")
  if defined(%s);
EOF
}

sub _inline_check_coercion {
	my $attr = (shift)->associated_attribute; 
	
	return '' unless $attr->should_coerce;
    return 'my $val = $attr->type_constraint->coerce($_[1]);'
}

sub _inline_check_required {
	my $attr = (shift)->associated_attribute; 
	
	return '' unless $attr->is_required;
    return 'defined($_[1]) || confess "Attribute ($attr_name) is required, so cannot be set to undef";'
}

sub _inline_check_lazy {
	my $attr = (shift)->associated_attribute; 
	
	return '' unless $attr->is_lazy;
	
	if ($attr->has_type_constraint) {
	    # NOTE:
	    # this could probably be cleaned 
	    # up and streamlined a little more
	    return 'unless (exists $_[0]->{$attr_name}) {' .
	           '    if ($attr->has_default) {' .
	           '        my $default = $attr->default($_[0]);' .
               '        (defined($type_constraint->($default)))' .
               '        	|| confess "Attribute (" . $attr->name . ") does not pass the type constraint ("' .
               '               . $attr->type_constraint->name . ") with " . (defined($default) ? "\'$default\'" : "undef")' .
               '          if defined($default);' .	                
	           '        $_[0]->{$attr_name} = $default; ' .
	           '    }' .
	           '    else {' .
               '        $_[0]->{$attr_name} = undef;' .
	           '    }' .
	           '}';	    
	}
    return '$_[0]->{$attr_name} = ($attr->has_default ? $attr->default($_[0]) : undef)'
         . 'unless exists $_[0]->{$attr_name};';
}


sub _inline_store {
	my ($self, $instance, $value) = @_;
	my $attr = $self->associated_attribute; 	

	my $mi = $attr->associated_class->get_meta_instance;
	my $slot_name = sprintf "'%s'", $attr->slots;

    my $code = $mi->inline_set_slot_value($instance, $slot_name, $value)    . ";";
	$code   .= $mi->inline_weaken_slot_value($instance, $slot_name, $value) . ";"
	    if $attr->is_weak_ref;
    return $code;
}

sub _inline_trigger {
	my ($self, $instance, $value) = @_;
	my $attr = $self->associated_attribute; 	
	return '' unless $attr->has_trigger;
	return sprintf('$attr->trigger->(%s, %s, $attr);', $instance, $value);
}

sub _inline_get {
	my ($self, $instance) = @_;
	my $attr = $self->associated_attribute; 	

	my $mi = $attr->associated_class->get_meta_instance;
	my $slot_name = sprintf "'%s'", $attr->slots;

    return $mi->inline_get_slot_value($instance, $slot_name);
}

sub _inline_auto_deref {
    my ( $self, $ref_value ) = @_;
	my $attr = $self->associated_attribute;     

    return $ref_value unless $attr->should_auto_deref;

    my $type_constraint = $attr->type_constraint;

    my $sigil;
    if ($type_constraint->is_a_type_of('ArrayRef')) {
        $sigil = '@';
    } 
    elsif ($type_constraint->is_a_type_of('HashRef')) {
        $sigil = '%';
    } 
    else {
        confess "Can not auto de-reference the type constraint '" . $type_constraint->name . "'";
    }

    "(wantarray() ? $sigil\{ ( $ref_value ) || return } : ( $ref_value ) )";
}

1;

__END__

#line 278