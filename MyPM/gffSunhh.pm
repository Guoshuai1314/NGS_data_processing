package gffSunhh; 
use strict; 
use warnings; 
use LogInforSunhh; 
use fileSunhh; 
use mathSunhh; 

##########################################################
#########  Basic settings. 
##########################################################

my $mathObj = mathSunhh->new(); 

##########################################################
#########  Methods. 
##########################################################
sub new {
	my $class = shift; 
	
	my $self = {}; 
	bless $self, $class; 
	
	$self->_initialize(@_); 
	
	return $self; 
}

sub _initialize {
	my $self = shift; 
}

# Function : 
# Input    : ('gffFH'=>&fileSunhh::openFH("in.gff3", "<"), 
#             'gffFile'=>"in.gff3", 
#             'saveFa'=>0, 
#             'debug'=>0, 
#             'top_hier'=>{ 'mrna'=>1, 'match'=>2, 'protein_match'=>3, 'expressed_sequence_match'=>4 }
#            )
# Return   : (\%back_gff, \%back_seq)
#  In %back_gff : 
#   {'lineN2line'}{$lineNum} = $line_txt; 
#   {'lineN2hash'}{$lineNum} = undef()     - for absent or skipped (blank of commented) lines 
#                              \%line_hash - for good gff3 lines parsed by $self->parse_line(); 
#   {'ID2lineN'}{$featID} = $lineNum; 
#   {'lineN2ID'}{$lineNum} = $featID; 
#    Here $featID = $ID_in_attribute or $lineNum if not assigned. 
#   {'PID2CID'}{$parent_featID}{$child_featID} = 1; 
#   {'CID2PID'}{$child_featID}{$parent_featID} = 1; 
#  In %back_seq : 
#   {'seqID'} = $fasta_seq_woBlank 
# Edit here. 
sub read_gff {
	my $self = shift; 
	my %parm = $self->_setHashFromArr(\@_); 
	### Step1. Setting parameters. 
	##   'saveFa' is used to keep fasta sequences in gff3 file into %back_seq hash. 
	$parm{'saveFa'} = $parm{'saveFa'} // 0; 
	##   Set the top hierarchy (featID should be in lower case!) to group features. 
	##   I plan to add the features who are parents of top_hier to the first group I output. 
	##   Some possible values:          
	##    contig
	##     gene
	##      mRNA
	##       five_prime_UTR/three_prime_UTR/exon/CDS
	##     match:match_part
	##     protein_match/expressed_sequence_match:match_part
	my %top_hier; 
	$self->_setTypeHash(\%top_hier, [qw/mrna match protein_match expressed_sequence_match/]); 
	if ( defined $parm{'top_hier'} ) {
		%top_hier = (); 
		$top_hier{lc($_)} = $parm{'top_hier'}->{$_} foreach (keys %{$parm{'top_hier'}}); 
	}
	##   Add 'fake' to the last of top_hier in order to get top_featID from absent line. 
	$self->_setTypeHash(\%top_hier, ["fake"]); 
	
	
	##   Checking for gff3 file handle. 
	##    First we check if 'gffFH' exists, then we require 'gffFile' if not found. 
	if ( !( defined $parm{'gffFH'} ) ) {
		if ( defined $parm{'gffFile'} ) {
			$parm{'gffFH'} = &fileSunhh::openFH($parm{'gffFile'}, '<'); 
		} else {
			&stopErr("[Err] Need gffFH or gffFile.\n"); 
		}
	}
	my $fh = $parm{'gffFH'}; 
	
	### Step2. Read in gff3 files. 
	##   %back_gff stores all line information in gff3. 
	##   %back_seq stores all sequence information in gff3. 
	my %back_gff; 
	my %back_seq; 
	my $is_seq = 0; # A sign indicating if we should read file as fasta now. 
	my $tkey = '';  # temporary key of fasta sequences. 
	while (my $line = <$fh>) {
		chomp($line); 
		### If the following lines are fasta sequences. 
		if ( $is_seq ) {
			if ( $line =~ m/^\s*\>/ ) {
				$line =~ m/^\s*\>(\S+)/ or &stopErr("[Err] $line.\n"); 
				$tkey = $1; 
			}else{
				$back_seq{$tkey} .= $line; 
			}
			next; 
		} elsif ( $line =~ m/^\s*\>/ ) {
			# I believe it should be a signal of fasta section. 
			$parm{'saveFa'} or last; 
			$is_seq = 1; 
			$line =~ m/^\s*\>(\S+)/ or &stopErr("[Err] $line.\n"); 
			$tkey = $1; 
			next; 
		}
		
		### If the current line is a not part of fasta sequence. 
		# A new (unique) number is assigned to every gff3_line. 
		my $lineNum = $mathObj->newNumber(); 
		$back_gff{'lineN2line'}{$lineNum} = $line; # Store all lines in 'lineN2line' hash_ref, and lines could be sorted by keys($lineNum); 
		$back_gff{'lineN2hash'}{$lineNum} = undef();  # There is no hash for line except parsable gff3_line. 
		
		### If the current line is null or lines that should be skipped, we record it and then go to next line. 
		$line =~ m/^\s*($|#)/ and next; 
		
		### If the current line is a good gff3_line
		## We parse the line to setup information. 
		my %line_hash = %{ $self->parse_line('line'=>$line, %parm) }; # Parse gff3_line. 
		# The featID is real ID or line number, both of which should be unique in the whole gff3 files. 
		my $featID = $lineNum ; 
		defined $line_hash{'attrib'} and defined $line_hash{'attrib'}{'featID'} and $featID = $line_hash{'attrib'}{'featID'}; 
		RE_CHK_FEATID_DUP: 
		if ( exists $back_gff{'ID2lineN'}{$featID} ) {
			my $new_featID = "${featID}:$lineNum"; 
			&tsmsg("[Wrn] Two lines have the same featID [$featID]. The latter one is changed to [$new_featID]. But it may still cause error.\n"); 
			$featID = $new_featID; 
			goto RE_CHK_FEATID_DUP; 
		}# Check featID duplication. 
		
		$back_gff{'ID2lineN'}{$featID} = $lineNum; 
		$back_gff{'lineN2ID'}{$lineNum} = $featID; 
		$back_gff{'lineN2hash'}{$lineNum} = \%line_hash; 
		
		## Setting up parent-child relationship. 
		if ( defined $line_hash{'attrib'} 
		  and defined $line_hash{'attrib'}{'parentID'} 
		  and keys %{ $line_hash{'attrib'}{'parentID'} } > 0 
		) {
			# parentID exists and we can record child relationships. 
			for my $pID ( keys %{ $line_hash{'attrib'}{'parentID'} } ) {
				$back_gff{'PID2CID'}{$pID}{$featID} = 1; 
				$back_gff{'CID2PID'}{$featID}{$pID} = 1; 
			}
		} else {
			# No parentID exists, and we may link it to itself. 
			# In this way, every feature has child relationship and is a key of 'PID2CID' and 'CID2PID'; 
			$back_gff{'PID2CID'}{$featID}{$featID} = 1; 
			$back_gff{'CID2PID'}{$featID}{$featID} = 1; 
		}
	}#End while() 
	### Step3. Remove blanks in %back_seq; 
	$back_seq{$_} =~ s/\s//g for (keys %back_seq); 
	
	### Step4. Check if the %back_gff is complete. 
	## Firstly, we can check if all featID in 'PID2CID'/'CID2PID' exist. 
	my @lost1 = grep { !(defined $back_gff{'ID2lineN'}{$_}) } keys %{$back_gff{'PID2CID'}}; 
	if (scalar(@lost1) > 0) {
		$parm{'debug'} and do { &tsmsg("[Wrn] ", scalar(@lost1), " featID in PID2CID not found, for example [$lost1[0]]\n"); }; 
		# give a lineNum to un-existing featID/PID; 
		for my $featID (@lost1) {
			my $lineNum = $mathObj->newNumber(); 
			$back_gff{'lineN2line'}{$lineNum} = ''; 
			$back_gff{'lineN2hash'}{$lineNum} = undef(); 
			$back_gff{'ID2lineN'}{$featID} = $lineNum; 
			$back_gff{'lineN2ID'}{$lineNum} = $featID; 
		}
	}
	my @lost2 = grep { !(defined $back_gff{'ID2lineN'}{$_}) } keys %{$back_gff{'CID2PID'}}; 
	if (scalar(@lost2) > 0) {
		$parm{'debug'} and do { &tsmsg("[Wrn] ", scalar(@lost2), " featID in CID2PID not found, for example [$lost2[0]]\n"); }; 
		# give a lineNum to un-existing featID/CID; 
		for my $featID (@lost2) {
			my $lineNum = $mathObj->newNumber(); 
			$back_gff{'lineN2line'}{$lineNum} = ''; 
			$back_gff{'lineN2hash'}{$lineNum} = undef(); 
			$back_gff{'ID2lineN'}{$featID} = $lineNum; 
			$back_gff{'lineN2ID'}{$lineNum} = $featID; 
		}
	}
	## Todo: Secondly, we can check and fix if the CDS_phase is given. 
	
	### Step5. We can group features by their highest or chosen hierarchy (%top_hier). 
	###  %uniq_top_featID stores all good top-parents' featID. 
	###  %lineN_group stores all line numbers of good topID and their parents and children. 
	###  The keys of %lineN_group are the keys in %uniq_top_featID, 
	###   and the values are {$topID}{'parLn'/'offLn'} ; 
	###   And %lineN_group is stored in $back_gff{'lineN_group'} as \%lineN_group; 
	##   Find out all featID in top level. 
	my %top_featID; # {PID} => hier_number 
	for my $pID (sort keys %{$back_gff{'PID2CID'}}) {
		my $lineNum = $back_gff{'ID2lineN'}{$pID}; 
		my $lineHR = $back_gff{'lineN2hash'}{$lineNum}; 
		my $featType = (defined $lineHR) ? lc($lineHR->{'type'}) : 'fake' ; 
		if ( defined $top_hier{$featType} ) {
			$top_featID{$pID} = $top_hier{$featType}; 
		}
	}#End for 
	##   Remove top_featID who is included by a better featID. 
	##    A uniq_top_featID is not another uniq_top_featID's child or parent. 
	my %uniq_top_featID; 
	for my $pID (
	  sort { $top_featID{$a} <=> $top_featID{$b} 
	    || $back_gff{'ID2lineN'}{$a} <=> $back_gff{'ID2lineN'}{$b} 
	  } 
	  keys %top_featID
	) {
		defined $uniq_top_featID{$pID} and next; 
		my $has_topID = 0; 
		# Checking offsprings
		my @off1 = @{ $self->_allChild( $pID, $back_gff{'PID2CID'} ) }; 
		for my $cID ( @off1 ) {
			defined $uniq_top_featID{$cID} and do { $has_topID = 1; last; }; 
		}
		$has_topID and next; 
		# Checking parents. 
		my @par1 = @{ $self->_allChild( $pID, $back_gff{'CID2PID'} ) }; 
		for my $cID ( @par1 ) {
			defined $uniq_top_featID{$cID} and do { $has_topID = 1; last; }; 
		}
		$has_topID and next; 
		
		# Here I use newNumber() which may not be very safe, but I do like it. 
		$has_topID or $uniq_top_featID{$pID} = $mathObj->newNumber(); 
	}# End for my $pID (sort { ... 
	
	##   Add other undefined top IDs. _allTopParent(); 
	##    This other_featID is not another uniq_top_featID's child or parent. 
	my %chked_featID = %top_featID; # Any of top_featID has a parent/child/itself in uniq_top_featID. 
	for my $cID1 ( sort { $back_gff{'ID2lineN'}{$a} <=> $back_gff{'ID2lineN'}{$b} } keys %{$back_gff{'CID2PID'}} ) {
		defined $chked_featID{$cID1} and next; # Skip this childID if it had been checked. 
		my @top1 = @{ $self->_allTopParent( $cID1, $back_gff{'CID2PID'} ) }; # Search for all top-parents of current child ID. 
		scalar(@top1) == 0 and @top1 = ($cID1); # The $cID1 itself is a top-parent. 
		
		for my $pID1 ( 
		  sort { 
		    $back_gff{'ID2lineN'}{$a} <=> $back_gff{'ID2lineN'}{$b} 
		      || &stopErr("[Err] topID [$a] and topID [$b] have same lineNum [$back_gff{'ID2lineN'}{$a}]\n") 
		  } 
		  @top1 
		) {
			defined $chked_featID{$pID1} and next; 
			$chked_featID{$pID1} = 1; 
			
			my $has_topID = 0; 
			
			# Checking offsprings. 
			my @off2 = @{ $self->_allChild( $pID1, $back_gff{'PID2CID'} ) }; 
			for my $cID2 (@off2) {
				defined $uniq_top_featID{$cID2} and do { $has_topID = 1; last; }; 
			}
			$has_topID and next; 
			# Checking parents. 
			my @par2 = @{ $self->_allChild( $pID1, $back_gff{'CID2PID'} ) }; 
			for my $cID2 (@par2) {
				defined $uniq_top_featID{$cID2} and do { $has_topID = 1; last; }; 
			}
			$has_topID and next; 
			
			# Here I use newNumber() which may not be very safe, but I do like it. 
			$has_topID or $uniq_top_featID{$pID1} = $mathObj->newNumber(); 
		}# End for my $pID1 
	}# End for my $cID1 ( sort { $back_gff{'ID2lineN'} ... 
	
	##   Now uniq_top_featID stores all good top-parents in the gff3 file. 
	##   So we can construct featID groups. 
	my %lineN_group; 
	my %group_lineN; 
	for my $topID (sort { $uniq_top_featID{$a} <=> $uniq_top_featID{$b} } keys %uniq_top_featID) { 
		my @par1_lineN = map { $back_gff{'ID2lineN'}{$_} } @{ $self->_allChild( $topID, $back_gff{'CID2PID'} ) }; 
		my @off1_lineN = map { $back_gff{'ID2lineN'}{$_} } @{ $self->_allChild( $topID, $back_gff{'PID2CID'} ) }; 
		if ( scalar(@par1_lineN) > 0 ) {
			@par1_lineN = sort { $a <=> $b } @par1_lineN; 
			$group_lineN{ $_ } = 1 for (@par1_lineN); 
		}
		if ( scalar(@off1_lineN) > 0 ) {
			@off1_lineN = sort { $a <=> $b } @off1_lineN; 
			$group_lineN{ $_ } = 1 for (@off1_lineN); 
		}
		$lineN_group{$topID}{'parLn'} = \@par1_lineN; # Offsprings 
		$lineN_group{$topID}{'offLn'} = \@off1_lineN; # Parents. 
		
		$group_lineN{ $back_gff{'ID2lineN'}{$topID} } = 1; 
	}# End for my $topID 
	##   Check if all good (Not skipped) gff3_lines grouped. 
	my @ln_LostInGrp; 
	for my $ln ( grep { defined $back_gff{'lineN2hash'}{$_} } keys %{$back_gff{'lineN2hash'}}) {
		defined $group_lineN{ $ln } or push(@ln_LostInGrp, $ln); 
	}
	if ( scalar(@ln_LostInGrp) > 0 ) {
		&stopErr("[Err] Line numbers that failed to be grouped: ", join(";", @ln_LostInGrp), "\n"); 
	}
	##   Record this information in back_gff{'lineN_group'}
	$back_gff{'lineN_group'} = \%lineN_group; 
	
	return (\%back_gff, \%back_seq); 
}# read_gff() 


# Input  : ( 'ta'=>[ split(/\t/, $gff_line) ], 'line'=>$gff_line )
# Return : \%backH
#  In %backH : 
#   $backH{'seqID'}  = $seqID; 
#   $backH{'srcID'}  = $srcID; 
#   $backH{'type'}   = $tType; 
#   $backH{'start'}  = $tS; 
#   $backH{'end'}    = $tE; 
#   $backH{'score'}  = $tScore; 
#   $backH{'strand'} = $tStr; 
#   $backH{'phase'}  = $tPhase; 
#   $backH{'attrib'} = \%attrHash; 
# Sample format: 
#  http://gmod.org/wiki/GFF3
#  http://www.sequenceontology.org/gff3.shtml
#  S401991_pilon   .       contig  1       99924   .       .       .       ID=S401991_pilon;Name=S401991_pilon
#  S401991_pilon   maker   gene    60810   79370   .       +       .       ID=maker-S401991_pilon-pred_gff_snap_masked-gene-0.7;Name=maker-S401991_pilon-pred_gff_snap_mask
#  Col_8:phase(0/1/2)  should be given if Col_3:type is "CDS"; 
#   For features of type "CDS", the phase indicates where the feature begins with reference to the reading frame. 
#   For forward strand features, phase is counted from the start field. For reverse strand features, phase is counted from the end field.
sub parse_line {
	my $self = shift; 
	my %parm = $self->_setHashFromArr(\@_); 
	my @ta; 
	if ( defined $parm{'ta'} ) {
		@ta = @{$parm{'ta'}}; 
	} elsif ( defined $parm{'line'} ) {
		chomp( $parm{'line'} ); 
		@ta = @{ $self->_txt2Array('txt'=>$parm{'line'}, %parm) }; 
	} else {
		&stopErr("[Err] Need {ta} or {line} parameter in parse_line.\n"); 
	}
	$self->_setEleParm(%parm); 
	
	my ($seqID, $srcID, $tType, $tS, $tE, $tScore, $tStr, $tPhase, $tAttrib) = @ta; 
	my %attrHash = %{ $self->_getAttrHash('attribText'=>$tAttrib, %parm) }; 
	my %backH; 
	$backH{'seqID'}  = $seqID; 
	$backH{'srcID'}  = $srcID; 
	$backH{'type'}   = $tType; 
	$backH{'start'}  = $tS; 
	$backH{'end'}    = $tE; 
	$backH{'score'}  = $tScore; 
	$backH{'strand'} = $tStr; 
	$backH{'phase'}  = $tPhase; 
	$backH{'attrib'} = \%attrHash; 
	
	# Retrieve parentID from tranID/geneID; 
	$self->_addParentID($backH{'attrib'}, %parm); 
	
	return \%backH; 
}# parse_line()


# Function : Trace all child ids by single parent ID. Parent ID itself not returned. 
# Input    : ( $parentID, $hash_parent2Child )
# Return   : [@childrenIDs]
sub _allChild {
	my $self = shift; 
	my $pID = shift; 
	my $p2c_hash = shift; # { {parentID} => {childID} => 1 } 
	my %parm = $self->_setHashFromArr(\@_); 
	$parm{'unique'} = $parm{'unique'} // 1; 
	return [ @{ $mathObj->offspringArray( $pID, sub { return keys %{ $p2c_hash->{$_[0]} }; }, %parm) } ]; 
}# _allChild()

# Function : Trace all top-parent ids by single child ID. Child ID itself not returned. 
#             Here top-parent means the parentID is not a child of any other ID. 
# Input    : ( $childID, $hash_child2parent )
# Return   : [@parentIDs]
sub _allTopParent {
	my $self = shift; 
	my $cID = shift; 
	my $c2p_hash = shift; # { {childID} => {parentID} => 1 }
	my %parm = $self->_setHashFromArr(\@_); 
	$parm{'unique'} = $parm{'unique'} // 1; 
	my @top1 = @{ $mathObj->offspringArray( $cID, sub { return keys %{ $c2p_hash->{$_[0]} }; }, %parm) }; 
	my @back_topID; 
	for my $pID (@top1) {
		if ( defined $c2p_hash->{$pID} ) {
			my $tn = scalar( keys %{$c2p_hash->{$pID}} ); 
			$tn > 1 and next; 
			( $tn == 1 and !(exists $c2p_hash->{$pID}{$pID}) ) and next; 
		}
		push(@back_topID, $pID); 
	}
	return [@back_topID]; 
}# _allTopParent() 

# Input  : (\%attrHash, 'typeIsCOT'=>\%typeIsCOT, 'typeIsCOG'=>\%typeIsCOG)
# Return : undef() 
# Function : Add 'tranID'/'geneID' as 'parentID' for some features. 
sub _addParentID {
	my $self = shift; 
	my $bkH = shift; 
	my %parm = $self->_setHashFromArr(\@_); 
	my %typeIsCOT; # type that is child of tranID; 
	%typeIsCOT = qw(
	  cds    1
	  exon   1
	  intron 1
	  stop_codon 1 
	  start_codon 1 
	  tss    1
	); 
	defined $parm{'typeIsCOT'} and %typeIsCOT = %{$parm{'typeIsCOT'}}; 
	my %typeIsCOG; # type that is child of geneID; 
	%typeIsCOG = qw( transcript 1 mrna 1 ); 
	defined $parm{'typeIsCOG'} and %typeIsCOG = %{$parm{'typeIsCOG'}}; 
	
	# Retrieve parentID information for augustus gff lines. 
	defined $bkH->{'type'} or return; # There are some lines 
	if ( defined $typeIsCOT{ lc($bkH->{'type'}) } and defined $bkH->{'attrib'}{'tranID'} ) {
		### Add tranID as parent ID. 
		for my $pID ( keys %{ $bkH->{'attrib'}{'tranID'} } ) {
			$bkH->{'attrib'}{'parentID'}{$pID} = $bkH->{'attrib'}{'parentID'}{$pID} // $bkH->{'attrib'}{'tranID'}{$pID}; 
		}
	}
	if ( defined $typeIsCOG{ lc($bkH->{'type'}) } and defined $bkH->{'attrib'}{'geneID'} ) {
		### Add geneID as parent ID. 
		for my $pID ( keys %{ $bkH->{'attrib'}{'geneID'} } ) {
			$bkH->{'attrib'}{'parentID'}{$pID} = $bkH->{'attrib'}{'parentID'}{$pID} // $bkH->{'attrib'}{'geneID'}{$pID}; 
		}
	}
	
	return; 
}#_addParentID() 

# Function: Read in Col_9 (attributes) of gff line, and parse the attributes information. 
#  
# Input  : ('attribText'=>"$ta[8]", 'debug'=>1)
# Return : \%backH 
#  In %backH : 
#   {'attribText'}   => $ta[8]
#   {'featID'} => Val (ID=)
#   {'tranID'} => {Val}=>nn (transcript_id "")
#   {'geneID'} => {Val}=>nn (gene_id "")
#   {'featName'} => Val (Name=)
#   {'parentID'} => {Val}=>nn (Parent=)
#   {'gapCigars'} => [M/I/D/F/R\d+, ...] (Gap=)
#   {'derives_from'} => {Val}=>nn (derives_from=)
#   {'note'} => Val (Note=)
#   {'dbxref'} => {Val}=>nn (Dbxref=)
#   {'Ontology_term'} => {Val}=>nn (Ontology_term=)
#   {'is_circular'} => 1/0 (Is_circular=)
#   {'alias'} => {Val}=>nn (Alias=)
sub _getAttrHash {
	my $self = shift; 
	my %parm = $self->_setHashFromArr(\@_); 
	$parm{'debug'} = $parm{'debug'} // 1; 
	defined $parm{'attribText'} or &stopErr("[Err] no {attribText} for _getAttrHash()\n"); 
	
	# Setting backH{key}=value; 
	my %backH; 
	$backH{'attribText'} = $parm{'attribText'}; 
	# Not complete. 
	for my $tag (qw/featID featName targetID targetS targetE targetStr gapID gapCigars parentID tranID geneID/) {
		$backH{$tag} = undef(); 
	}
	# {key} => {} : tranID geneID parentID derives_from dbxref Ontology_term alias
	
	
	my @tv_pairs = ( $backH{'attribText'} =~ m/\s*([^\s;]+)(?:=|\s+)\s*([^\s;]+[^;]*)(?:\s*;|\s*$)/g ); 
	if ( $#tv_pairs == -1 ) {
		$parm{'debug'} and &tsmsg("[Wrn] No attribute information found in [$backH{'attribText'}]\n"); 
	} else {
		# Add tag=value pairs to %backH; 
		$#tv_pairs % 2 == 0 and $parm{'debug'} and &tsmsg("[Wrn] Attributes parsed wrong in [$backH{'attribText'}]\n"); 
		for (my $i=0; $i<@tv_pairs; $i+=2) {
			my ($tag, $val) = @tv_pairs[$i, $i+1]; 
			$tag = lc($tag); 
			if ( $tag eq 'id') {
				$backH{'featID'} = $val; 
			} elsif ( $tag eq 'transcript_id' ) {
				$val =~ s!^"|"$!!g; 
				$backH{'tranID'} = $backH{'tranID'} // {}; 
				$self->_setTypeHash( $backH{'tranID'}, $self->_txt2Array('txt'=>$val, 'sepSym'=>",")  ); 
			} elsif ( $tag eq 'gene_id' ) {
				$val =~ s!^"|"$!!g; 
				$backH{'geneID'} = $backH{'geneID'} // {}; 
				$self->_setTypeHash( $backH{'geneID'}, $self->_txt2Array('txt'=>$val, 'sepSym'=>",")  ); 
			} elsif ( $tag eq 'name' ) {
				$backH{'featName'} = $val; 
			} elsif ( $tag eq 'target' ) {
				if ( $val =~ m/^(\S+)(?:\s*(\d+)\s*(\d+)\s*([+-])?)?/ ) {
					my ($t1, $t2, $t3, $t4) = ($1, $2, $3, $4); 
					$backH{'targetID'}  = $t1; 
					$backH{'targetS'}   = $t2; 
					$backH{'targetE'}   = $t3; 
					$backH{'targetStr'} = $t4; 
				} else {
					$parm{'debug'} and &tsmsg("[Wrn] Unknown target format in [$val]\n"); 
				}
			} elsif ( $tag eq 'parent' ) {
				$backH{'parentID'} = $backH{'parentID'} // {}; 
				$self->_setTypeHash( $backH{'parentID'}, $self->_txt2Array('txt'=>$val, 'sepSym'=>",")  ); 
			} elsif ( $tag eq 'gap' ) {
				my @cig = ( $val =~ m/([A-Z]\d+)/g ); # I don't want to use m//i because it should not be in lower case. 
				for my $tC (@cig) {
					if ( $tC =~ m/^M(\d+)/) { # match
						push(@{$backH{'gapCigars'}}, $tC); 
					} elsif ( $tC =~ m/^I(\d+)/ ) { # insert a gap into the reference sequence
						push(@{$backH{'gapCigars'}}, $tC); 
					} elsif ( $tC =~ m/^D(\d+)/ ) { # insert a gap into the target (delete from reference) 
						push(@{$backH{'gapCigars'}}, $tC); 
					} elsif ( $tC =~ m/^F(\d+)/ ) { # frameshift forward in the reference sequence 
						push(@{$backH{'gapCigars'}}, $tC); 
					} elsif ( $tC =~ m/^R(\d+)/ ) { # frameshift reverse in the reference sequence 
						push(@{$backH{'gapCigars'}}, $tC); 
					} else {
						&tsmsg("[Wrn] Unknown cigar [$tC]\n"); 
					}
				}
			} elsif ( $tag eq 'derives_from' ) {
				$backH{'derives_from'} = $backH{'derives_from'} // {}; 
				$self->_setTypeHash( $backH{'derives_from'}, $self->_txt2Array('txt'=>$val, 'sepSym'=>",")  ); 
			} elsif ( $tag eq 'note') {
				$backH{'note'} = $val; 
			} elsif ( $tag eq 'dbxref' ) {
				$backH{'dbxref'} = $backH{'dbxref'} // {}; 
				$self->_setTypeHash( $backH{'dbxref'}, $self->_txt2Array('txt'=>$val, 'sepSym'=>",")  ); 
			} elsif ( $tag eq 'Ontology_term' ) {
				$backH{'Ontology_term'} = $backH{'Ontology_term'} // {}; 
				$self->_setTypeHash( $backH{'Ontology_term'}, $self->_txt2Array('txt'=>$val, 'sepSym'=>",")  ); 
			} elsif ( $tag eq 'is_circular' ) {
				if ( $val =~ m/^T(rue)?$/i ) {
					$backH{'is_circular'} = 1; 
				} elsif ( $val =~ m/^F(alse)?$/i ) {
					$backH{'is_circular'} = 0; 
				} else {
					&tsmsg("[Wrn] Unknown is_circular value [$val]\n"); 
				}
			} elsif ( $tag eq 'alias' ) {
				$backH{'alias'} = $backH{'alias'} // {}; 
				$self->_setTypeHash( $backH{'alias'}, $self->_txt2Array('txt'=>$val, 'sepSym'=>",")  ); 
			} else {
				&tsmsg("[Wrn] Skip unknown attribute_tag [$tag=$val]\n"); 
			}
		}# End for (my $i=0; $i<@tv_pairs; $i+=2)  
	}# End if () 
	
	return \%backH; 
}# _getAttrHash() 

sub _txt2Array {
	my $self = shift; 
	my %parm = $self->_setHashFromArr(\@_); 
	defined $parm{'txt'} or return [] ; 
	$parm{'sepSym'} = $parm{'sepSym'} // "\t"; 
	my $sepSym = $parm{'sepSym'}; 
	$parm{'noTrimBlank'} = $parm{'noTrimBlank'} // 0; 
	my @backA; 
	for my $tE (split(/$sepSym/, $parm{'txt'})) {
		$parm{'noTrimBlank'} or $tE =~ s!^\s+|\s+$!!g; 
		push(@backA, $tE); 
	}
	return \@backA; 
}# _txt2Array() 

# Input  : (  'type2include'  => {'match'=>1, 'match_part'=>2}, 
#             'type2separate' => {'match'=>1} , 
#             'type2check'    => { { keys %{ $parm{'type2include'} } } => 1 } , 
#             %parm)
# Output : undef()
# Function : Set default values for $parm{qw/type2include type2separate type2check/}; 
sub _setParmType {
	my $self = shift; 
	my %parm = $self->_setHashFromArr(\@_); 
	defined $parm{'type2include'}  or &_setTypeHash('', $parm{'type2include'},   [ qw/match match_part/ ]); 
	defined $parm{'type2separate'} or &_setTypeHash('', $parm{'type2separate'},  [ qw/match/ ]); 
	defined $parm{'type2check'}    or &_setTypeHash('', $parm{'type2check'},     [ sort { $parm{'type2include'}{$a} <=> $parm{'type2include'}{$b} || $a cmp $b } keys %{$parm{'type2include'}} ]); 
	return; 
}# _setParmType()

# Input  : ($hashRef_to_setup, $arrayRef1_as_keys, $arrayRef2_as_keys, ...)
# Return : undef() 
# Function: Use @$arrayRef1_as_keys as keys to fill %$hashRef_to_setup; 
sub _setTypeHash {
	my $self = shift; 
	my $hr = shift; 
	my $aa = 0; 
	for (keys %$hr) {
		$aa < $hr->{$_} and $aa = $hr->{$_}; 
	}
	$aa ++; 
	for my $ar (@_) {
		( defined $ar and scalar(@$ar) > 0 ) or next; 
		$hr->{lc($_)} = $aa++ for ( grep { !(defined $hr->{lc($_)}) } @$ar ) ; 
		( defined $ar and scalar(@$ar) > 0 ) and last; 
	}
	return; 
}# _setTypeHash()

sub _setEleParm {
	my $self = shift; 
	return; 
}# _setEleParm()

sub _setHashFromArr {
	my $self = shift; 
	my $arr_ref = shift; 
	my %back_hash; 
	for (my $i=0; $i<@$arr_ref; $i+=2) {
		my $val; 
		if (exists $arr_ref->[$i+1]) {
			$val = $arr_ref->[$i+1]; 
		} else {
			exists $back_hash{$arr_ref->[$i]} or &tsmsg("[Wrn] Input array is not even! Use undef() for key [", $arr_ref->[$i],"]\n"); 
			$val = undef(); 
		}
		exists $back_hash{$arr_ref->[$i]} or $back_hash{$arr_ref->[$i]} = $val; 
	}
	return(%back_hash); 
}# _setHashFromArr() 

1; 