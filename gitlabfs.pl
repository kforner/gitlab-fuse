#!/usr/bin/env perl
use strictures 1;
use Smart::Comments -ENV;
use GitLab::API::v3;
use GitLab::API::v3::Constants qw( :all );



use Getopt::Long;
use Pod::Usage qw( pod2usage );

Getopt::Long::Configure('pass_through');

GetOptions(
    'url=s'    => \my $url,
    'token=s'  => \my $token,
    'help'     => \my $help,
    'verbose'  => \my $verbose,
    'quiet'    => \my $quiet,
) or die "ERROR: Unable to process options!\n";

if ($help or @ARGV and $ARGV[0] eq 'help') {
    pod2usage( -verbose => 2 );
    exit 0;
}

my ($mount_point) = @ARGV;
$mount_point ||= glob("~/.gitlabfs");

### using mount point: $mount_point
mkdir($mount_point) unless -e $mount_point;

$url   ||= $ENV{GITLAB_API_V3_URL};
$token ||= $ENV{GITLAB_API_V3_TOKEN};

pod2usage('give url and token') unless $url and $token;


my $api = GitLab::API::v3->new(
    url   => $url,
    token => $token,
    );

### api: $api

my $projects = $api->all_projects();
my @pnames = map { $_->{name_with_namespace}} @$projects;
### pnames: @pnames
use Fuse qw(fuse_get_context);
use POSIX qw(ENOENT EISDIR EINVAL);

my $readonly = 0644;


my (%tree) = (
    '/' => {
	projects => {
	    type => 0040,
	    mode => $readonly,
	    ctime => time(),
	},
    }
);


my (%files) = (
    projects => {
	type => 0040,
	mode => $readonly,
	ctime => time(),
    },
    
    '.' => {
	type => 0040,
	mode => 0755,
	ctime => time()-1000
    }
);

# populate groups from projects
#my @groups = map { } @pnames;
    
sub populate {
    my $file = shift;
    ### populate() - file: $file 
    if ($file =~ /projects/) {

    }
}	
    
sub filename_fixup {
	my ($file) = shift;
	$file =~ s,^/,,;
	$file = '.' unless length($file);
	return $file;
}

sub e_getattr {
    my $file = shift;
    ### getattr file: $file
    
    $file = filename_fixup($file);
    #### getattr, after fixup file: $file
    $file =~ s,^/,,;
     #### getattr, after s// file: $file
	$file = '.' unless length($file);
	return -ENOENT() unless exists($files{$file});
	my ($size) = exists($files{$file}{cont}) ? length($files{$file}{cont}) : 0;
	$size = $files{$file}{size} if exists $files{$file}{size};
	my ($modes) = ($files{$file}{type}<<9) + $files{$file}{mode};
	my ($dev, $ino, $rdev, $blocks, $gid, $uid, $nlink, $blksize) = (0,0,0,1,0,0,1,1024);
	my ($atime, $ctime, $mtime);
	$atime = $ctime = $mtime = $files{$file}{ctime};
	# 2 possible types of return values:
	#return -ENOENT(); # or any other error you care to
	#print(join(",",($dev,$ino,$modes,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)),"\n");
	return ($dev,$ino,$modes,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks);
}

sub e_getdir {
    my $dir = shift;
    ### getdir dir: $dir
	# return as many text filenames as you like, followed by the retval.
    #print((scalar keys %files)."\n");
    my $files = $tree{$dir} or return -ENOENT();
    
    return (keys %$files),0;
}

sub e_open {
	# VFS sanity check; it keeps all the necessary state, not much to do here.
    my $file = filename_fixup(shift);
    my ($flags, $fileinfo) = @_;
    print("open called $file, $flags, $fileinfo\n");
	return -ENOENT() unless exists($files{$file});
	return -EISDIR() if $files{$file}{type} & 0040;
    
    my $fh = [ rand() ];
    
    print("open ok (handle $fh)\n");
    return (0, $fh);
}

sub e_read {
	# return an error numeric, or binary/text string.  (note: 0 means EOF, "0" will
	# give a byte (ascii "0") to the reading program)
	my ($file) = filename_fixup(shift);
    my ($buf, $off, $fh) = @_;
    print "read from $file, $buf \@ $off\n";
    print "file handle:\n", Dumper($fh);
	return -ENOENT() unless exists($files{$file});
	if(!exists($files{$file}{cont})) {
		return -EINVAL() if $off > 0;
		my $context = fuse_get_context();
		return sprintf("pid=0x%08x uid=0x%08x gid=0x%08x\n",@$context{'pid','uid','gid'});
	}
	return -EINVAL() if $off > length($files{$file}{cont});
	return 0 if $off == length($files{$file}{cont});
	return substr($files{$file}{cont},$off,$buf);
}

sub e_statfs { return 255, 1, 1, 1, 1, 2 }

# If you run the script directly, it will run fusermount, which will in turn

Fuse::main(
	mountpoint=>$mount_point,
	getattr=>"main::e_getattr",
	getdir =>"main::e_getdir",
	open   =>"main::e_open",
	statfs =>"main::e_statfs",
	read   =>"main::e_read",
	threaded=>0
);





__END__

=head1 NAME

gitlabfs - gitlab virtual filesystem.

=head1 SYNOPSIS

    # Generally:
    gitlabfs [mount_point]

=head1 ARGUMENTS

=head2 url

    --url=<url>

The URL to to your GitLab API v3 API base.  Typically this will
be something like C<http://git.example.com/api/v3>.

You can alternatively set this by specifying the C<GITLAB_API_V3_URL>
environment variable.

=head2 token

    --token=<token>

The API token to access the API with.

Alternatively you can set the C<GITLAB_API_V3_TOKEN> environment
variable.

WARNING: As a general rule it is highly discouraged to put sensitive
information into command arguments such as your private API token since
arguments can be seen by other users of the system.  Please use the
environment variable if possible.

=head2 help

    help
    --help

Displays this handy documentation.

=head1 SEE ALSO

L<GitLab::API::v3>

=head1 AUTHOR

Karl Forner <karl.forner@gmail.com>

=head1 LICENSE

This script is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

