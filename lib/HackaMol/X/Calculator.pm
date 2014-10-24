package HackaMol::X::Calculator;

# ABSTRACT: Abstract calculator class for HackaMol
use 5.008;
use Moose;
use Moose::Util::TypeConstraints;
use Capture::Tiny ':all';
use File::chdir;
use Carp;

with qw(HackaMol::ExeRole HackaMol::PathRole);

has 'mol' => (
    is  => 'ro',
    isa => 'HackaMol::Molecule',
);

has 'map_in' => (
    is        => 'ro',
    isa       => 'CodeRef',
    predicate => 'has_map_in',
);
has 'map_out' => (
    is        => 'ro',
    isa       => 'CodeRef',
    predicate => 'has_map_out',
);

#some setup
sub BUILD {
    my $self = shift;

    if ( $self->has_scratch ) {
        $self->scratch->mkpath unless ( $self->scratch->exists );
    }

    #build command
    unless ( $self->has_command ) {
        return unless ( $self->has_exe );
        my $cmd = $self->build_command;
        $self->command($cmd);
    }
    return;
}

sub build_command {

# the command won't be overwritten during build, but may be overwritten with this method
    my $self = shift;
    my $cmd;
    $cmd = $self->exe;
    $cmd .= " " . $self->in_fn->stringify    if $self->has_in_fn;
    $cmd .= " " . $self->exe_endops          if $self->has_exe_endops;
    $cmd .= " > " . $self->out_fn->stringify if $self->has_out_fn;

    # no cat of out_fn because of options to run without writing, etc
    return $cmd;
}

sub map_input {

    # pass everything and anything to map_in... i.e. keep @_ in tact
    my ($self) = @_;
    unless ( $self->has_in_fn and $self->has_map_in ) {
        carp "in_fn and map_in attrs required to map input";
        return 0;
    }
    local $CWD = $self->scratch if ( $self->has_scratch );
    my $input = &{ $self->map_in }(@_);

# $self->in_fn->spew($input); leaving such actions inside the map_in coderef is more flexible
# too flexible?
    return $input;
}

sub map_output {

    # pass everything and anything to map_out... i.e. keep @_ in tact
    my ($self) = @_;
    unless ( $self->has_out_fn and $self->has_map_out ) {
        carp "out_fn and map_out attrs required to map output";
        return 0;
    }
    local $CWD = $self->scratch if ( $self->has_scratch );
    my $output = &{ $self->map_out }(@_);
    return $output;
}

sub capture_sys_command {

    # run it and return all that is captured
    my $self    = shift;
    my $command = shift;
    unless ( defined($command) ) {
        return 0 unless $self->has_command;
        $command = $self->command;
    }

    local $CWD = $self->scratch if ( $self->has_scratch );
    my ( $stdout, $stderr, $exit ) = capture {
        system($command);
    };
    return ( $stdout, $stderr, $exit );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

HackaMol::X::Calculator - Abstract calculator class for HackaMol

=head1 VERSION

version 0.00_4

=head1 SYNOPSIS

   use Modern::Perl;
   use HackaMol;
   use HackaMol::X::Calculator;

   my $hack = HackaMol->new( 
                             name => "hackitup" , 
                             data => "local_pdbs",
                           );
    
   my $i = 0;

   foreach my $pdb ($hack->data->children(qr/\.pdb$/)){

      my $mol = $hack->read_file_mol($pdb);

      my $Calc = HackaMol::X::Calculator->new (
                    molecule => $mol,
                    scratch  => 'realtmp/tmp',
                    in_fn    => 'calc.inp'
                    out_fn   => "calc-$i.out"
                    map_in   => \&input_map,
                    map_out  => \&output_map,
                    exe      => '~/bin/xyzenergy < ', 
      );     
 
      $Calc->map_input;
      $Calc->capture_sys_command;
      my $energy = $Calc->map_output(627.51);

      printf ("Energy from xyz file: %10.6f\n", $energy);

      $i++;

   }

   #  our functions to map molec info to input and from output
   sub input_map {
     my $calc = shift;
     $calc->mol->print_xyz($calc->in_fn);
   }

   sub output_map {
     my $calc   = shift;
     my $conv   = shift;
     my @eners  = map { /ENERGY= (-*\d+.\d+)/; $1*$conv } 
                  grep {/ENERGY= -*\d+.\d+/} $calc->out_fn->lines; 
     return pop @eners; 
   }

=head1 DESCRIPTION

The HackaMol::X::Calculator extension generalizes molecular calculations using external programs. 
The Calculator class consumes roles provided by the HackaMol core that manages the running of 
executables... perhaps on files; perhaps in directories.  This extension is intended to provide a 
simple example of interfaces with external programs. It is probably too flexible. New extensions 
can evolve from this starting point, in scripts, to more rigid encapsulated classes. In the synopsis,
The input is written (->map_input), the command is run (->capture_sys_command) and the output is 
processed (->map_output).  Thus, the calculator can be used to 1. generate inputs, 2. run programs, 3. 
process outputs.

=head1 METHODS

=head2 map_input

changes to scratch directory, if set, and passes all arguments (including self) to 
map_in CodeRef. Thus, any input writing must 

  $calc->map_input(@args);

will invoke,

  &{$calc->map_in}(@_);  #where @_ = ($self,@args)

and return anything returned by the map_in function.

=head2 map_output

completely analogous to map_input.  Thus, the output must be opened and processed in the
map_out function.

=head2 build_command 

builds the command from the attributes: exe, inputfn, exe_endops, if they exist, and returns
the command.

=head2 capture_sys_command

uses Capture::Tiny capture method to run a command using a system call. STDOUT, STDERR, are
captured and returned.

  my ($stdout, $stderr,@other) = capture { system($command) }

the $command is taken from $calc->command unless the $command is passed,

  $calc->capture_sys_command($some_command);

capture_sys_command returns ($stdout, $stderr,@other) or 0 if there is no command set.

=head1 ATTRIBUTES

=head2 scratch

Coerced to be 'Path::Tiny' via AbsPath. If scratch is set, all work is carried out in that 
directory.  See HackaMol::PathRole for more information about the scracth attribute.

=head2 mol

isa HackaMol::Molecule that is ro and required

=head2 map_in

isa CodeRef that is ro

intended for mapping input files from molecular information, but it is completely
flexible. Used in map_input method.  Can also be directly ivoked,

  &{$calc->map_in}(@args); 

as any other subroutine would be.

=head2 map_out

intended for mapping molecular information from output files, but it is completely
flexible and analogous to map_in. 

=head1 EXTENDS

=over 4

=item * L<Moose::Object>

=back

=head1 CONSUMES

=over 4

=item * L<HackaMol::ExeRole>

=item * L<HackaMol::ExeRole|HackaMol::PathRole>

=item * L<HackaMol::PathRole>

=back

=head1 AUTHOR

Demian Riccardi <demianriccardi@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Demian Riccardi.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
