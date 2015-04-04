package fastaSunhh; 
use strict; 
use warnings; 
use LogInforSunhh; 
use fileSunhh; 
use mathSunhh; 

##########################################################
#########  Basic settings.
##########################################################
my $mathObj = mathSunhh->new(); 
my %str2num = qw(
  +      1
  -     -1
  1      1
  -1    -1
  plus   1
  minus -1
  0     -1
); 


##########################################################
#########  Methods.
##########################################################

=head1 fastaSunhh->new()

Function     : Open an object of fastaSunhh

=cut
sub new {
	my $class = shift; 
	my $self = {}; 
	bless $self, $class; 
	
	$self->_initialize(@_); 
	
	return $self; 
}#sub new

sub _initialize {
	my $self = shift; 
	
	my %parm = $mathObj->_setHashFromArr(@_); 
	for my $k ( keys %parm ) {
		$self->{$k} = $parm{$k}; 
	}
	
	return; 
}#sub _initialize

=head2 save_seq_to_hash( 'faFh'=>$faFileHandle, 'faFile'=>$faFileName, 'has_head'=>[1/0] )

Required     : 'faFh' , or 'faFile' when 'faFh' missed. 

Function     : Save all sequences' information in hash

Return       : (\%key_to_infor)
 \%key_to_infor : {key} => value
   {$seq_ID}      => \%seq_record_hash; 
     \%seq_record_hash : {key} => value 
       {'head'}       => the line heading with '>', but with heading '>' removed; 
       {'key'}        => sequence ID ; 
       {'definition'} => Same to 'head' except that 'key' is removed. 
       {'seq'}        => sequence information in the same format of input. 
       {'has_get'}   => Tell if there is another sequence in the next. 
       {'FH'}         => File handle being used. 

=cut
sub save_seq_to_hash {
	my $self = shift; 
	my %parm = $mathObj->_setHashFromArr(@_); 
	my $fh = $parm{'faFh'} // &fileSunhh::openFH($parm{'faFile'}, '<') // &stopErr("[Err] No valid file handle in get_fasta_seq()\n"); 
	$parm{'has_head'} //= 1; 
	$parm{'has_head'} =~ m/^0+$/ or $parm{'has_head'} = 1; 
	ref($fh) eq 'GLOB' or ref($fh) eq '' or &stopErr("[Err] File handle wrong.\n"); 
	
	my %backH; 
	# For the first sequence; 
	{
		my $relHR = $self->get_fasta_seq( 'faFh'=>$fh, 'has_head'=>$parm{'has_head'} ); 
		if ( $relHR->{'has_get'} == 1 ) {
			$backH{$relHR->{'key'}} = $relHR; 
		}
	}
	for (my $relHR = $self->get_fasta_seq( 'faFh'=>$fh ); $relHR->{'has_get'} == 1; $relHR = $self->get_fasta_seq( 'faFh'=>$fh ) ) {
		if ( defined $backH{ $relHR->{'key'} } ) {
			&tsmsg("[Err] Key [$relHR->{'key'}] repeated, and I choose the first one.\n"); 
			next; 
		}
		$backH{ $relHR->{'key'} } = $relHR; 
	}
	
	return (\%backH); 
}# sub save_seq_to_hash () 

=head2 get_fasta_seq('faFh'=>$faFileHandle, 'faFile'=>$faFileName, 'has_head'=>[1/0])

Required     : 'faFh' , or 'faFile' when 'faFh' missed. 

Function     : Input a fasta file's handle and a signal showing whether it has a head line, 
                 then it returns a hash storing one sequence record once. 
Return       : (\%seq_record_hash)
 \%seq_record_hash : {key} => value 
   {'head'}       => the line heading with '>', but with heading '>' removed; 
   {'key'}        => sequence ID ; 
   {'definition'} => Same to 'head' except that 'key' is removed. 
   {'seq'}        => sequence information in the same format of input. 
   {'has_get'}   => Tell if there is another sequence in the next. 
   {'FH'}         => File handle being used. 

Example      : 
 
my $fs = fastaSunhh->new(); 
my $inFa = "tt.fa"; 
my $inFh = &openFH($inFa, "<"); # Input file handle 
# for (my $relHR = $fs->get_fasta_seq('faFh'=>$inFh); $relHR->{'has_get'} == 1; $relHR = $fs->get_fasta_seq('faFh'=>$inFh) ) {
for (my $relHR = $fs->get_fasta_seq('faFile'=>$inFa); $relHR->{'has_get'} == 1; $relHR = $fs->get_fasta_seq('faFh'=>$relHR->{'FH'}) ) {
	my $seq_id  = $relHR->{'key'}; 
	my $seq_seq = $relHR->{'seq'}; $seq_seq =~ s!\s!!g; 
	my $seq_head = $relHR->{'head'}; 
	my $seq_def  = $relHR->{'definition'}; 
}
# All sequences in $inFh have been processed. 
=cut
sub get_fasta_seq {
	my $self = shift; 
	my %parm = $mathObj->_setHashFromArr(@_); 
	my $fh = $parm{'faFh'} // &fileSunhh::openFH($parm{'faFile'}, '<') // &stopErr("[Err] No valid file handle in get_fasta_seq()\n"); 
	$parm{'has_head'} //= 1; 
	$parm{'has_head'} =~ m/^0+$/ or $parm{'has_head'} = 1; 
	ref($fh) eq 'GLOB' or ref($fh) eq '' or &stopErr("[Err] File handle wrong.\n"); 
	
	my %backH; 
	$backH{'has_get'} = 0; 
	$backH{'FH'} = $fh; 
	# Retrieve head information. 
	if ( $parm{'has_head'} == 1 ) {
		defined ( $backH{'head'} = readline($fh) ) or return (\%backH); 
		$backH{'head'} =~ s!^>!!g; chomp($backH{'head'}); 
		( $backH{'definition'} = $backH{'head'} ) =~ s!^(\S+)!!; 
		$backH{'key'} = $1; 
		$backH{'has_get'} = 1; 
	}
	# Retrieve sequence information. 
	my $r = $/; local $/ = "$r>"; 
	unless ( defined ( $backH{'seq'} = readline($fh) ) ) {
		$parm{'has_head'} and &tsmsg("[Wrn] The last sequence [$backH{'head'}] is empty, so it is not calculated!\n");
		return (\%backH); 
	}
	( chomp($backH{'seq'}) ) > length($r) and $backH{'has_get'} = 1; 
	local $/ = $r; chomp($backH{'seq'}); 
	
	# Check if this sequence is a NULL one. 
	# When the sequence is a NULL one, the $backH{'seq'} will read the next whole sequence including the header line. 
	# So I want to fix this error. 
	while ($backH{'seq'} =~ s!^>!!gs) {
		&tsmsg("[Wrn] Sequence [$backH{'head'}] is empty, and it is skipped!\n"); 
		# if ( $backH{'seq'} =~ s!^([^$r]+)(?:$r|$)!!s ) {
		if ( $backH{'seq'} =~ s!^(.+)(?:$r|$)!!s ) { # I prefer to edit this line because I am afraid of Nt/Nr database fasta. 
			$backH{'definition'} = $backH{'head'} = $1; 
			chomp( $backH{'definition'} ); chomp( $backH{'head'} ); 
			$backH{'definition'} =~ s!^(\S+)!!; $backH{'key'} = $1; 
		}
	}
	
	return (\%backH); 
}# sub get_fasta_seq ()




1; 
