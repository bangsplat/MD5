#!/usr/bin/perl
use strict;	# Enforce some good programming rules
#use warnings;

use Getopt::Long;
use Cwd;
use File::Find;
use Digest::MD5;
use File::stat;

# md5.pl
#
# version 2.1.1
#
# I don't know why I didn't add this to the repository a long time ago
# it's a very old script
# 
# calculate md5 value of a file or string
# primary use is to recursively hash every file in a directory and subdirectory
# 
# flags:
#
# --help | -?				display help/syntax
# --mode [ file | directory | string ]	operation mode
#						file - process only one file
#						directory - directory search, optionally recursive
#						string - process input string
# --file | -f				input file - may exclude the -f
# --filter <regex>			file name filter - process only if name matches regex
# --directory | -d			specifies starting directory (default is current working dir)
# --[no]recurse | -[no]r		recursively search subfolders in directory mode
# --[no]output | -[no]o			output to .md5 file - default no
# --[no]digest				digest output for multiple files into a single text file
# --[no]size | -[no]s			include file size info in output - default no
# --[no]name | -[no]n			include file name in output - default no
# --string <string>			string to checksum for string mode
# --[no]debug				display debug information
# --[no]test				test mode - display file names but do not process

sub xor($$);

my ( $help_param, $file_param, $output_param, $size_param, $name_param, $debug_param, $leftover_param );
my ( $mode_param, $filter_param, $test_param, $directory_param, $digest_param, $string_param, $recurse_param );
my ( $version_param );
my ( $md5, $md5_value, $file_size, $file_stat );
my ( $output_filename, $output_string, $output_digest );
my ( $xor_value, $total_size_value );

GetOptions(	'help|?'	=> \$help_param,
        'version'   =>  \$version_param,
		'mode=s'	=> \$mode_param,
		'string=s'	=> \$string_param,
		'file|f=s'	=> \$file_param,
		'filter=s'	=> \$filter_param,
		'directory|d=s'	=> \$directory_param,
		'recurse|r!'	=> \$recurse_param,
		'output|o!'	=> \$output_param,
		'digest!'	=> \$digest_param,
		'size|s!'	=> \$size_param,
		'name|n!'	=> \$name_param,
		'debug!'	=> \$debug_param,
		'test!'		=> \$test_param );

# grab any parameters left over in case that's our filename list
$leftover_param = $ARGV[0];

## debug: display parameters
if ( $debug_param ) {
	print "Passed Parameters:\n";
	print "help = $help_param\n";
	print "version = $version_param\n";
	print "mode = $mode_param\n";
	print "string = $string_param\n";
	print "file = $file_param\n";
	print "filter = $filter_param\n";
	print "directory = $directory_param\n";
	print "recurse = $recurse_param\n";
	print "output = $output_param\n";
	print "digest = $digest_param\n";
	print "size = $size_param\n";
	print "name = $name_param\n";
	print "debug = $debug_param\n";
	print "test = $test_param\n";
	print "leftover = $leftover_param\n";
	print "\n";
}

# if the user asked for version information, display it and quit
if ( $version_param ) {
    print "$0 version 2.1\n";
    exit;
}

# if user asked for help or does not pass any parameters, display help message and exit
if ( $help_param ) {
	print "md5.pl\n";
	print "Version 2.1\n\n";
	print "Calculates MD5 checksum signatures for files.\n\n";
	print "Requires Perl 5.8 or later.\n\n";
	print "Command line parameters:\n\n";
	print "--mode [ file | directory | string ] - operating mode:\n\n";
	print "    file - process a single file\n";
	print "    directory - process directory and, optionally, subdirectories\n";
	print "    string - process string\n";
	print "Default is directory mode.\n\n";
	print "--file | -f <filename> - in file mode, specifies the file to process.\n";
	print "<filename> is required, but --file | -f may be omitted.\n\n";
	print "--directory | -d <directory> - in directory mode,\n";
	print "specifies the starting directory for processing.\n";
	print "Default is the current working directory. --directory | -d may be omitted.\n\n";
	print "--string <string> - in string mode, specifies the string to process.\n";
	print "<string> is required, but --string may be omitted.\n\n";
	print "--filter <regex> - in directory mode, specifies a filename filter for processing\n";
	print "<regex> is a regular expression.\n\n";
	print "--[no]recurse | -[no]r - in directory mode,\n";
	print "recursively processes files in subdirectories.\n";
	print "Default is to recursively process files in subdirectories.\n\n";
	print "--[no]output | -[no]o - in file and directory mode, output results to file.\n\n";
	print "In file mode, default is off - output is to STDIO.\n";
	print "In directory mode, default is on - output to file.\n\n";
	print "--[no]digest - in directory mode, output all results into one digest file.\n";
	print "Default is off - output each result to an individual file.\n\n";
	print "--[no]name | -[no]n - include file name in output.\n";
	print "Default is on if digesting output, otherwise off.\n\n";
	print "--[no]size | -[no]s - include file size (in bytes) in output.\n";
	print "Default is on.\n\n";
	print "--version display version information\n";
	print "--help | -h - display this message\n";
	exit;
}

# set parameter defaults
if ( $debug_param eq undef ) { $debug_param = 0; }		# false
if ( $test_param eq undef ) { $test_param = 0; }		# false
if ( $mode_param eq undef ) { $mode_param = "directory"; }	# directory mode
# --file parameter only makes sense in file mode
if ( $mode_param eq "file" ) {
	if ( $file_param eq undef ) {
		if ( $leftover_param eq undef ) {
			print "Must specify an input file in file mode\n";
			exit;
		} else {
			$file_param = $leftover_param;
		}
	}
}
# --string parameter only makes sense in string mode
if ( $mode_param eq "string" ) {
	if ( $string_param eq undef ) {
		if ( $leftover_param eq undef ) {
			print "Must specify an input string in string mode\n";
			exit;
		} else { $string_param = $leftover_param; }
	}
}
if ( $mode_param eq "directory" ) {
	if ( $directory_param eq undef ) {
		if ( $leftover_param eq undef ) { $directory_param = cwd; }
		else { $directory_param = $leftover_param; }
	}
}
if ( $recurse_param eq undef ) { $recurse_param = 1; }		# true
# --output parameter default depends on mode
if ( $output_param eq undef ) {
	if ( $mode_param eq "directory" ) { $output_param = 1; }	# true in directory mode
	else { $output_param = 0; }					# false otherwise
}
if ( $output_param ) {
	if ( $digest_param eq undef ) { $digest_param = 0; }		# default to false
} else { $digest_param = 0; }						# false if output is false
if ( $size_param eq undef ) { $size_param = 1; }		# true
# --name parameter defalut depends on --digest setting
if ( $name_param eq undef ) {
	if ( $digest_param ) { $name_param = 1; }		# true if --digest is true
	else { $name_param = 0; }				# false
}
# no default value for --filter

## debug: display parameters
if ( $debug_param ) {
	print "Final Parameters:\n";
	print "help = $help_param\n";
	print "version = $version_param\n";
	print "mode = $mode_param\n";
	print "string = $string_param\n";
	print "file = $file_param\n";
	print "filter = $filter_param\n";
	print "directory = $directory_param\n";
	print "recurse = $recurse_param\n";
	print "output = $output_param\n";
	print "digest = $digest_param\n";
	print "size = $size_param\n";
	print "name = $name_param\n";
	print "debug = $debug_param\n";
	print "test = $test_param\n";
	print "leftover = $leftover_param\n";
	print "\n";
}

# zero out the rolling XOR value
$xor_value = "00000000000000000000000000000000";
$total_size_value = 0;

# from here, what we do depends on the mode

if ( $mode_param eq "file" ) {		# file mode
	if ( $debug_param ) { print "file mode: $file_param\n"; }
	if ( $test_param ) { print "TEST: $file_param\n"; }	# test mode output - don't process file
	else {
		open( INPUT_FILE, "<", $file_param )	# open input file
			or die "Can't open input file $file_param\n";
		binmode( INPUT_FILE );				# set to binary mode
		if ( $debug_param ) { print "open input file $file_param\n"; }

		$md5 = Digest::MD5->new;			# create MD5 object
		$md5->addfile( *INPUT_FILE );			# calculate MD5 of input file
		$md5_value = $md5->hexdigest;			# get the hex version of the MD5
		if ( $debug_param ) { print "MD5: $md5_value\n"; }

		# get file size
		$file_stat = stat( $file_param );
		$file_size = $file_stat->size;
		if ( $debug_param ) { print "input file size: $file_size\n"; }

		# form output string
		$output_string = $md5_value;
		if ( $size_param ) { $output_string .= "\t$file_size"; }	# include file size if requested
		if ( $name_param ) { $output_string .= "\t$file_param"; }	# include file name if requested
		$output_string .= "\n";
		
		close( INPUT_FILE )				# close the input file
			or warn "Error closing input file\n";
		if ( $debug_param ) { print "close input file\n"; }

		$output_filename = $file_param.".md5";	# create .md5 filename
		if ( $debug_param ) { print "output filename: $output_filename\n"; }

		if ( $output_param ) {
			open( OUTPUT_FILE, ">", $output_filename )	# open output file
				or die "Can't open output file $output_filename";
			if ( $debug_param ) { print "open output file $output_filename\n"; }

			print( OUTPUT_FILE "$output_string\n" );	# write output string
			if ( $debug_param ) { print "write output string to output file\n"; }

			close( OUTPUT_FILE )				# close output file
				or warn "Error closing output file\n";
			if ( $debug_param ) { print "close output file\n"; }
		} else {
			print "$output_string\n";		# output to STDIO
		}
	}
} elsif ( $mode_param eq "directory" ) {	# directory mode
	if ( $debug_param ) { print "directory mode\n"; }
	
	$output_digest = "";	# clear out digest
	
	# do the recursive directory search thing
	chdir( $directory_param );	# change to the target directory
	find( \&doittoit, "." ); 	# begin file filtering
	
	if ( $digest_param ) {
		
		$output_filename = "digest.md5";		# create digest file name
		if ( $debug_param ) { print "output digest file:$output_filename\n"; }
		
		open( OUTPUT_FILE, ">", $output_filename )	# open output file
			or die "Can't open file $output_filename";
		if ( $debug_param ) { print "open digest file $output_filename\n"; }
		
		print( OUTPUT_FILE $output_digest );		# write output string
		if ( $debug_param ) { print "write digest string to output file\n"; }
		
		# add rolling XOR value to end of digest file
		print( OUTPUT_FILE "\n$xor_value\t$total_size_value\n" );
		
		close( OUTPUT_FILE )				# close output file
			or warn "Error closing output file\n";
		if ( $debug_param ) { print "close output file\n"; }
	}
} elsif ( $mode_param eq "string" ) {		# string mode
	if ( $debug_param ) { print "string mode: $string_param\n"; }
	if ( $test_param ) { print "TEST: $string_param\n"; }	# test mode output - don't process string
	else {
		# get MD5 value of string
		$md5 = Digest::MD5->new;
		$md5->add( $string_param );
		$md5_value = $md5->hexdigest;
		if ( $debug_param ) { print "MD5: $md5_value\n"; }
		
		$output_string = $md5_value;				# put md5 into output string

		if ( $size_param ) {
			$file_size = length( $string_param );		# get sting size if requested
			$output_string .= "\t$file_size";		# append string length
		}

		print "$output_string\n";				# return checksum
	}
}

sub doittoit {
	# process only files, either in the base directory or if --recurse is on
	# and if no filter or if the file matches the filter
	if ( ( ( $recurse_param || $File::Find::dir eq "." ) && ( ! -d ) ) &&
	( $filter_param eq undef || ( ( $filter_param ne undef ) && ( /$filter_param/ ) ) ) ) {
		my $full_path = $directory_param . "/" . $File::Find::name;	# create full path
		$full_path =~ s/\\/\//g;					# turn around any backwards slashes
		$full_path =~ s/\/.\//\//;					# remove extra "/./"
		$full_path =~ s/\/\//\//g;					# remove any duplicate slashes
		if ( -d ) { $full_path .= "/"; }				# add slash to directory names
				
		if ( $test_param ) { print "TEST: $_\n"; }	# test mode - don't process file
		else {
			open( INPUT_FILE, "<", $full_path )	# open input file
				or die "Can't open input file $_\n";
			binmode( INPUT_FILE );
			if ( $debug_param ) { print" open input file $_\n"; }
			
			$md5 = Digest::MD5->new;			# create MD5 object
			$md5->addfile( *INPUT_FILE );			# calculate MD5 of input file
			$md5_value = $md5->hexdigest;			# get the hex version of the MD5
			if ( $debug_param ) { print "MD5: $md5_value\n"; }
			
			# get file size
			$file_stat = stat( $full_path );
			$file_size = $file_stat->size;
			if ( $debug_param ) { print "input file size: $file_size\n"; }
			
			# form output string
			$output_string = $md5_value;
			if ( $size_param ) { $output_string .= "\t$file_size"; }
			if ( $name_param ) { $output_string .= "\t$_"; }
			if ( $debug_param ) { print "output string: $output_string\n"; }

			close( INPUT_FILE )				# close the input file
				or warn "Error closing input file\n";
			if ( $debug_param ) { print "close input file\n"; }
			
			# add the output to digest string
			$output_digest .= "$output_string\n";
			
			# XOR the hash value against our rolling value
			# I believe this works - it seems to in my testing anyway
			$xor_value = &xor( $xor_value, $md5_value );
			
			# add the file size to the total_size_value
			$total_size_value += $file_size;
            
			$output_filename = $_.".md5";	# create .md5 filename
			if ( $debug_param ) { print "output filename: $output_filename\n"; }
			
			if ( $output_param ) {				# output the results to a file
				if (  !$digest_param ) {		# but if a digest, don't do it now
					open( OUTPUT_FILE, ">", $output_filename )	# open output file
						or die "Can't open output file $output_filename";
					if ( $debug_param ) { print "open output file $output_filename\n"; }

					print( OUTPUT_FILE "$output_string\n" );	# write output string
					if ( $debug_param ) { print "write output string to output file\n"; }

					close( OUTPUT_FILE )				# close output file
						or warn "Error closing output file\n";
					if ( $debug_param ) { print "close output file\n"; }
				}
			} else { print "$output_string\n"; }		# otherwise output to STDIO
		}
	}
}

sub xor($$) {
    my $param1 = shift(@_);
    my $param2 = shift(@_);
    my $formatString = "H" . min( length( $param1 ), length( $param2 ) );
    my $output = pack( $formatString, $param1 ) ^ pack( $formatString, $param2 );
    my $outputStr = unpack( $formatString, $output );
    return( $outputStr );
}

sub min($$) {
    my $a = shift(@_);
    my $b = shift(@_);
    
    if ( $a < $b ) { return( $a ) } else { return( $b ); }
}
