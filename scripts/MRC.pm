#!/usr/bin/perl -w

#MRC.pm - The MRC workflow manager

package MRC;

use strict;
use IMG::Schema;
use Data::Dumper;
use File::Basename;

sub new{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    my @fcis  = (6);
    $self->{"fci"}     = \@fcis; #family construction ids that are allowed to be processed
    $self->{"workdir"} = undef; #master path to MRC scripts
    $self->{"ffdb"} = undef; #master path to the flat file database
    $self->{"dbi"}  = undef; #DBI string to interact with DB
    $self->{"user"} = undef; #username to interact with DB
    $self->{"pass"} = undef; #password to interact with DB
    $self->{"schema"} = undef; #current working DB schema object (DBIx)
    $self->{"projectpath"} = undef;
    $self->{"projectname"} = undef;
    $self->{"project_id"}   = undef;
    bless($self);
    return $self;
}

sub set_fcis{

}

sub set_scripts_dir{
    my $self = shift;
    my $path = shift;
    $self->{"workdir"} = $path;
    return $self->{"workdir"};
}

sub set_flat_file_db{
    my $self = shift;
    my $path = shift;
    $self->{"ffdb"} = $path;
    return $self->{"ffdb"};
}

sub set_dbi_connection{
    my $self = shift;
    my $path = shift;
    $self->{"dbi"} = $path;
    return $self->{"dbi"};
}

sub set_username{
    my $self = shift;
    my $path = shift;
    $self->{"user"} = $path;
    return $self->{"user"};
}

sub set_password{
    my $self = shift;
    my $path = shift;
    $self->{"pass"} = $path;
    return $self->{"pass"};
}

sub build_schema{
    my $self = shift;
    my $schema = IMG::Schema->connect( $self->{"dbi"}, $self->{"user"}, $self->{"pass"} );
    $self->{"schema"} = $schema;
    return $self->{"schema"};
}

sub set_project_id{
    my $self = shift;
    my $pid  = shift;
    $self->{"project_id"} = $pid;
    return $self->{"project_id"};
}

sub subset_families{
    my $self   = shift;
    my $subset = shift;
    my $check  = shift;
    #if no subset was provided, grab all famids that match our fcis. this could get big, so we might change in the future
    if( !defined( $subset ) ){
	warn "You did not specify a subset of family ids to process. Processing all families that meet FCI criteria.\n";
	my @all_ids = ();
	foreach my $fci( @{ $self->{"fci"} } ){	    
	    my @ids = $self->{"schema"}->resultset('Family')->search( { familyconstruction_id => $fci } )->get_column( 'famid' )->all;
	    @all_ids = ( @all_ids, @ids );
	}
	$self->{"fid_subset"} = \@all_ids;
    }
    else{
	#process the subset file. one famid per line
	open( SUBSET, $subset ) || die "Can't open $subset for read: $!\n";
	my @retained_ids = ();
	while( <SUBSET> ){
	    chomp $_;
	    push( @retained_ids, $_ );
	}
	close SUBSET;
        #let's make sure they're all from the proper family contruction id                                                                                           
	if( $check == 1 ){
	    my $correct_fci = 0;
	    my @correct_ids = ();
	    my @fcis = @{ $self->{"fci"} }; #get the passable construction ids
	  FID: foreach my $fid( @retained_ids ){
	      foreach my $fci( @fcis ){
		  my $fam_construct_id = $self->{"schema"}->resultset('Family')->find( { famid => $fid } )->get_column( 'familyconstruction_id' );
		  if( $fam_construct_id == $fci ){
		      $correct_fci++;
		      push( @correct_ids, $fid );
		      next FID;
		  }
	      }
	  }
	    warn "Of the ", scalar(@retained_ids), " family subset ids you provided, $correct_fci have a desired family construction id\n";
	    @retained_ids = ();
	    $self->{"fid_subset"} = \@correct_ids;
	}
	#We've checked their fci in the past. skip this process and accept everything.
	else{
	    #store the raw array as a reference in our project object
	    $self->{"fid_subset"} = \@retained_ids;
	}
    }
    return $self->{"fid_subset"};
}

sub get_subset_famids{
    my $self = shift;
    return $self->{"fid_subset"};
}

#returns samples result set
sub get_samples_by_project_id{
    my $self    = shift;
    my $samples = $self->{"schema"}->resultset("Sample")->search(
	{
	    project_id => $self->{"project_id"},
	}
    );
    return $samples;
}

sub load_project{
    my $self    = shift;
    my $path    = shift;
    my $text    = shift;
    my $samples = shift; #hashref
    #get project name and load
    my ( $name, $dir, $suffix ) = fileparse( $path );        
    my $proj = $self->create_project( $name, $text );    
    my $pid  = $proj->project_id();
    warn( "Loading project $pid, files found at $path\n" );
    #store vars in object
    $self->{"projectpath"} = $path;
    $self->{"projectname"} = $name;
    $self->{"project_id"}   = $pid;
    #process the samples associated with project
    $self->load_samples( $samples );
    warn( "Project $pid successfully loaded!\n" );
    return $self;
}

sub create_project{
    my $self = shift;
    my $name = shift;
    my $text = shift;
    my $proj_rs = $self->{"schema"}->resultset("Project");
    my $inserted = $proj_rs->create(
	{
	    name => $name,
	    description => $text,
	}
	);
    return $inserted;
}

sub load_samples{
    my $self   = shift;
    my $rsamps = shift;
    my %samples = %{ $rsamps };

    my $samps = scalar( keys(%samples) ) - 1;
    warn( "Processing $samps samples associated with project $self->{'project_id'}\n" );
    foreach my $sample( keys( %samples ) ){	
	next if $sample =~ m/DESCRIPTION/;
	my $insert  = $self->create_sample( $sample, $self->{"project_id"} );    
	my $sid     = $insert->sample_id();
	print "project ID: $self->{'project_id'}\tsample ID: $sid\n";
	my $seqs    = Bio::SeqIO->new( -file => $samples{$sample}, -format => 'fasta' );
	my $count   = 0;
	while( my $read = $seqs->next_seq() ){
	    my $read_name = $read->display_id();
	    $self->create_metaread( $read_name, $sid );
	    $count++;
	}
	warn("Loaded $count reads into DB for sample $sid\n");
    }
    warn( "All samples associated with project $self->{'project_id'} are loaded\n" );
    return $self;
}

sub create_sample{
    my $self = shift;
    my $sample_name = shift;
    my $project_id = shift;
    
    my $proj_rs = $self->{"schema"}->resultset("Sample");
    my $inserted = $proj_rs->create(
	{
	    sample_alt_id => $sample_name,
	    project_id => $project_id,
	}
	);
    return $inserted;
}

sub create_metaread{
    my $self = shift;
    my $read_name = shift;
    my $sample_id = shift;

    my $proj_rs = $self->{"schema"}->resultset("Metaread");
    my $inserted = $proj_rs->create(
	{
	    sample_id => $sample_id,
	    read_alt_id => $read_name,
	}
	);
    return $inserted;
}

#this is a compute side function. don't use db vars
sub translate_reads{
    

}

#the efficiency of this method could be improved!
sub load_orf{
    my $self        = shift;
    my $orf_alt_id  = shift;
    my $read_alt_id = shift;
    my $sampref     = shift;
    my %samples     = %{ $sampref };
    my $reads = $self->{"schema"}->resultset("Metaread")->search(
	{
	    read_alt_id => $read_alt_id,
	}
    );
    while( my $read = $reads->next() ){
	my $sample_id = $read->sample_id();
	if( exists( $samples{$sample_id} ) ){
	    my $read_id = $read->read_id();
	    $self->insert_orf( $orf_alt_id, $read_id, $sample_id );
	    #A project cannot have identical reads in it (same DNA string ok, but must have unique alt_ids)
	    last;
	}
    }
}

sub insert_orf{
    my $self       = shift;
    my $orf_alt_id = shift;
    my $read_id    = shift;
    my $sample_id  = shift;
    my $orf = $self->{"schema"}->resultset("Orf")->create(
	{
	    read_id    => $read_id,
	    sample_id  => $sample_id,
	    orf_alt_id => $orf_alt_id,
	}
    );
    return $orf;
}

sub get_rand_geneid{
    my $self  = shift;
    my $famid = shift;
    my $schema = $self->{"schema"};
    my $fm_rs = $schema->resultset("Familymember");
    my $fammembers = $fm_rs->search({ famid => $famid });
    my $rand = int( rand( $fammembers->count() ) );
    my @geneids = $fammembers->get_column('gene_oid')->all();
    my $rand_id = $geneids[$rand-1];
#    print "$rand_id\t$famid\n";
    return $rand_id;
}

sub get_gene_by_id{
    my( $self, $geneid ) = @_;
    print "$geneid\n";
    my $gene = $self->{"schema"}->resultset('Gene')->find( { gene_oid => $geneid } );
    return $gene;
}

#we will convert a gene row into a three element hash: the unqiue gene_oid key, the protein id, and the nucleotide sequence. the same
#proteins may be in the DB more than once, so we will track genes by their gene_oid (this will be the bioperl seq->id() tag)
sub print_gene{
    my ( $self, $geneid, $seqout ) = @_;
    my $gene = $self->get_gene_by_id( $geneid );
    my $sequence = $gene->get_column('dna');
    my $desc     = $gene->get_column('protein_id');
    my $seq = Bio::Seq->new( -seq        => $sequence,
			     -alphabet   => 'dna',
			     -display_id => $geneid,
			     -desc       => $desc
	);
    $seqout->write_seq( $seq );
}

1;