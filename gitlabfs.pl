#!/usr/bin/env perl
use strict;
use warnings;
use Smart::Comments -ENV;
use GitLab::API::v3;
use GitLab::API::v3::Constants qw( :all );
use File::Basename;
use List::MoreUtils qw(uniq);
use Memoize;

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

memoize('gitlab_fetch_projects');


my $api = GitLab::API::v3->new(
    url   => $url,
    token => $token,
    );

### api: $api

sub gitlab_fetch_projects {
	my $projects = $api->all_projects();
	my @pnames = map { $_->{name_with_namespace}} @$projects;

	return \@pnames;
}


use Fuse qw(fuse_get_context);
use POSIX qw(ENOENT EISDIR EINVAL);

my $READONLY = 0644;
my $DEFAULT_TYPE = 0040;
my $DEFAULT_BLOCKSIZE = 1024;



sub dir_entry {
	my ($name) = @_;
	return {
		type => $DEFAULT_TYPE,
	    mode => $READONLY,
	    ctime => time(),
	};
}

sub is_dir_equal {
	my ($dir, $ref) = @_;

	$ref .= '/' unless $ref =~ m|/$|;
	$dir .= '/' unless $dir =~ m|/$|;

	return $ref eq $dir;
}

sub getattr_error { return -ENOENT() }



sub getattr_dir {
	my ($size, $type) = @_;
	$size //= 0;
	$type //= $DEFAULT_TYPE;

	my $mode = $READONLY;
	my $modes = ($type<<9) + $mode;
	my ($dev, $ino, $rdev, $blocks, $gid, $uid, $nlink, $blksize) = (0,0,0,1,0,0,1,$DEFAULT_BLOCKSIZE);
	my ($atime, $ctime, $mtime);
	$atime = $ctime = $mtime = time();

	return ($dev,$ino,$modes,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks);
}

sub getattr_file {
	my ($size, $type) = @_;
	$size //= 0;
	$type //= $DEFAULT_TYPE;

	my $mode = $READONLY;
	my ($modes) = ($type<<9) + $mode;
	my ($dev, $ino, $rdev, $blocks, $gid, $uid, $nlink, $blksize) = (0,0,0,1,0,0,1,$DEFAULT_BLOCKSIZE);
	my ($atime, $ctime, $mtime);
	$atime = $ctime = $mtime = time();

	return ($dev,$ino,$modes,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks);
}



sub filename_fixup {
	my ($file) = shift;
	$file =~ s,^/,,;
	$file = '.' unless length($file);
	return $file;
}

sub gitlab_getattr {
    my $path = shift;
    ### gitlab_getattr $path: $path

	return getattr_dir() if $path eq '/';

	return gitlab_getattr_projects($path) if $path =~ qw{/projects};

	### gitlab_getattr: ignoring entry: $path
	return -ENOENT();
}

sub gitlab_getattr_projects {
    my $path = shift;
    ### gitlab_getattr_projects $path: $path

	return getattr_dir() if is_dir_equal($path, '/projects/');

	return getattr_dir() if $path =~ m|/projects/([^/]+){1,2}|;

	### gitlab_getattr: ignoring entry: $path
	return -ENOENT();
}

sub gitlab_getdir {
    my $dir = shift;
    ### gitlab_getdir dir: $dir

	return gitlab_getdir_root()	if $dir eq '/';

	return gitlab_getdir_projects($dir) if $dir =~ m|/projects|;

    return -ENOENT();
}

sub gitlab_getdir_root {
    return ("projects"), 0;
}

sub gitlab_getdir_projects {
	my $dir = shift;

	### gitlab_getdir_projects dir: $dir
	return gitlab_getdir_project_groups($dir) if is_dir_equal($dir, '/projects/');

	return gitlab_getdir_project_group($dir);
    return ("projects"), 0;
}

sub gitlab_getdir_project_groups {
	my $dir = shift;

	### gitlab_getdir_project_groups dir: $dir
	my $pnames = gitlab_fetch_projects();
	### $pnames: $pnames

	my @groups = sort(uniq(
		map {
			my ($dir) = ($_ =~ m|(.*)\s+/|);
			$dir;
		} @$pnames));

	#### @groups: @groups

    return (@groups), 0;
}

sub gitlab_getdir_project_group {
	my $dir = shift;

	### gitlab_getdir_project_group dir: $dir
	my $pnames = gitlab_fetch_projects();
	### $pnames: $pnames



}


sub e_open {
#	# VFS sanity check; it keeps all the necessary state, not much to do here.
#    my $file = filename_fixup(shift);
#    my ($flags, $fileinfo) = @_;
#    print("open called $file, $flags, $fileinfo\n");
#	return -ENOENT() unless exists($files{$file});
#	return -EISDIR() if $files{$file}{type} & 0040;
#
#    my $fh = [ rand() ];
#
#    print("open ok (handle $fh)\n");
#    return (0, $fh);
}

sub e_read {
#	# return an error numeric, or binary/text string.  (note: 0 means EOF, "0" will
#	# give a byte (ascii "0") to the reading program)
#	my ($file) = filename_fixup(shift);
#    my ($buf, $off, $fh) = @_;
#    print "read from $file, $buf \@ $off\n";
#    print "file handle:\n", Dumper($fh);
#	return -ENOENT() unless exists($files{$file});
#	if(!exists($files{$file}{cont})) {
#		return -EINVAL() if $off > 0;
#		my $context = fuse_get_context();
#		return sprintf("pid=0x%08x uid=0x%08x gid=0x%08x\n",@$context{'pid','uid','gid'});
#	}
#	return -EINVAL() if $off > length($files{$file}{cont});
#	return 0 if $off == length($files{$file}{cont});
#	return substr($files{$file}{cont},$off,$buf);
}

sub e_statfs { return 255, 1, 1, 1, 1, 2 }

# If you run the script directly, it will run fusermount, which will in turn

Fuse::main(
	mountpoint => $mount_point,
	getattr => "main::gitlab_getattr",
	getdir => "main::gitlab_getdir",
	open   => "main::e_open",
	statfs => "main::e_statfs",
	read   => "main::e_read",
	threaded => 0
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

