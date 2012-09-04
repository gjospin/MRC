#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use File::Path qw(make_path rmtree);
use IPC::System::Simple qw(capture $EXITVAL);

#called by lighthouse, executes run_hmmscan.sh. Note this is different than the lighthouse variant!.
print "perl run_remote_hmmscan_handler.pl @ARGV\n";

my( $results_dir, $hmmdb_dir, $query_seq_dir, $hmmdb_name, $waittime, $scriptpath );

GetOptions(
    "o=s" => \$results_dir,
    "h=s" => \$hmmdb_dir,
    "i=s" => \$query_seq_dir,	  
    "n=s" => \$hmmdb_name,
    "w=i" => \$waittime,
    "s=s" => \$scriptpath,	   
    );

print "working with $hmmdb_dir\n";
print "running searches\n";
#create a jobid storage log
my %jobs = ();
#open the query seq file directorie (e.g., /orfs/) and grab all of the orf splits
opendir( IN, $query_seq_dir ) || die "Can't opendir $query_seq_dir for read in run_remote_hmmscan_handler.pl\n";
my @query_files = readdir( IN );
closedir( IN );
#loop over the files, launching a queue job for each
foreach my $query_seq_file( @query_files ){
    next if( $query_seq_file =~ m/^\./ );
    #modify results_dir here such that the output is placed into each split's subdir w/in $results_dir
    my $split_sub_results_dir = $results_dir . $query_seq_file . "/";
    #now let's see if that directory exists. If not, create it.
    check_and_make_path( $split_sub_results_dir, 0 );
    #run the jobs!
    my $results = run_remote_search( $scriptpath, $query_seq_dir, $query_seq_file, $hmmdb_dir, $hmmdb_name, $split_sub_results_dir ); 
#    my $results = run_remote_search( $scriptpath, $query_seq_dir, $query_seq_file, $hmmdb_dir, $hmmdb_name, $results_dir ); 
    if( $results =~ m/^Your job-array (\d+)\./ ) {
	my $job_id = $1;
	$jobs{$job_id}++;
    }
    else{
	warn( "Remote server did not return a properly formatted job id when running transeq on (remote) localhost. Got $results instead!. Exiting.\n" );
	exit(0);
    }
}

#At this point, we have a lot ofjobs in the queue. Let's monitor the queue and report back to local when jobs are complete 
my @job_ids = keys( %jobs );
my $time = remote_job_listener( \@job_ids, $waittime );


###############
# SUBROUTINES #
###############

sub run_remote_search{
    my( $scriptpath, $query_seq_dir, $query_seq_file, $hmmdb_dir, $hmmdb_name, $results_dir ) = @_;
    print "Processing $query_seq_file\n";    
    print "Running with array jobs....\n";
    #need to make it so that these are passed in through the function...
    my $results = run_hmmscan( $scriptpath, $query_seq_dir, $query_seq_file, $hmmdb_dir, $hmmdb_name, $results_dir );
    #we can add other classification methods here at a later date (e.g., run blast)
    return $results;

}

sub run_hmmscan{
    my( $scriptpath, $query_seq_dir, $query_seq_file, $hmmdb_dir, $hmmdb_name, $results_dir ) = @_;
    my $hmm_out_stem = $query_seq_file . "-" . $hmmdb_name;
    my @args = ( $scriptpath, $query_seq_dir, $query_seq_file, $hmmdb_dir, $results_dir, $hmm_out_stem );
    print( "qsub ", "@args\n" );
    my $results = capture( "qsub " . "@args" );
    if( $EXITVAL != 0 ){
        warn( "Error running transeq on remote server: $results\n" );
        exit(0);
    }
    return $results;
}

sub remote_job_listener{
    my $jobs     = shift;
    my $waittime = shift;
    my $numwaits = 0;
    my %status   = ();
     while(1){
        #stop checking if every job has a finished status
        last if( scalar( keys( %status ) ) == scalar( @{ $jobs } ) );
        #call qstat and grab the output
        my $results = execute_qstat();
        #see if any of the jobs are complete. pass on those we've already finished
        foreach my $jobid( @{ $jobs } ){
            next if( exists( $status{$jobid} ) );
            if( $results !~ m/$jobid/ ){
                $status{$jobid}++;
            }
        }
        sleep( $waittime );
        $numwaits++
    }
    my $time = $numwaits * $waittime;
    return $time;
}

sub execute_qstat{
    my $cmd = shift;
    my $results = capture( "qstat" );
    if( $EXITVAL != 0 ){
	warn( "Error running execute_cmd: $results\n" );
    }
    return $results;
}

sub check_and_make_path{
    my( $path, $force, $disregard_force ) = @_;
    if( -d $path && !$force ){
	if( defined( $disregard_force ) && !$disregard_force ){
            warn( "Directory exists at $path, will not overwrite without force!\n" );
            exit(0);
	}
    }
    elsif( -d $path && $force ){
	warn( "...removing $path\n" );
	rmtree( $path ) || die "can't rmtree:$!\n";
	warn( "...creating $path\n" );
	make_path( $path ) || die "can't make_path: $!\n";
    }
    else{
        warn( "..creating an directory at $path\n");
	make_path( $path );
    }
    return 1;
}
