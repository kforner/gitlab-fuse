#!/usr/bin/env perl
use strict;
use warnings;
use Smart::Comments -ENV;

my $DEFAULT_PERMISSIONS = 0555; # u+rw,g+r,o+r
my $TYPE_DIR = 0040000;
my $TYPE_SYMLINK = 0120000;
my $TYPE_FILE =  0100000;
my $DEFAULT_TYPE = $TYPE_FILE;
my $DEFAULT_BLOCKSIZE = 1024;


package FsObj;
use Moose;
use POSIX qw(ENOENT EISDIR EINVAL);
has 'name' => (is      => 'ro', isa => 'Str');
has 'size' => (is      => 'ro', isa => 'Int', default => 0);
has 'type' => (is      => 'ro', isa => 'Int', default => $TYPE_FILE);

sub getdir { return -ENOENT() }
sub getattr { return -ENOENT() }
sub open { die 'not yet implemented' }
sub read { die 'not yet implemented' }

package FsFile;
use Moose;
extends 'FsObj';

sub getattr {
	my $self = shift;
	main::make_getattr(size => $self->size, type => $self->type);
}

package FsDir;
use Moose;
extends 'FsObj';

has 'files' => (
	is      => 'rw',
	isa     => 'ArrayRef[Str]',
    default => sub { [] }
	);

sub getdir {
	my $self = shift;
	return (@{$self->files()}, 0);
}

sub getattr {
	my $self = shift;
	main::make_getattr(size => $self->size, type => $TYPE_DIR);
}

package FsGroups;
use Moose; extends 'FsDir';

before 'getdir' => sub {
	my $self = shift;
	$self->files([$self->_fetch_group_names()]) unless @{$self->files};
};

sub _fetch_group_names {
	map { $_->{full_name} }  @{Gitlab::fetch_groups()}
}

package FsGroup;
use Moose; extends 'FsDir';

before 'getdir' => sub {
	my $self = shift;
	$self->files([$self->_fetch_group_project_names()]) unless @{$self->files};
};

sub _fetch_group_project_names {
	my $self = shift;
	map { $_->{name} }  @{Gitlab::fetch_group_projects($self->name)}
}

package FsProject;
use Moose; extends 'FsDir';
has 'group' => (is  => 'ro', isa => 'Str', required => 1);

before 'getdir' => sub {
	my $self = shift;
	$self->files([$self->_fetch_file_names()]) unless @{$self->files};
};

sub _fetch_file_names {
	my $self = shift;
	my $tree = Gitlab::fetch_project_tree($self->group, $self->name);
	map { $_->{name} }  @{$tree};
}


package FsTree;
use Moose; extends 'FsObj';
has 'group' => (is  => 'ro', isa => 'Str', required => 1);
has 'project' => (is  => 'ro', isa => 'Str', required => 1);
has 'path' => (is  => 'ro', isa => 'Str', required => 1);
has 'entry' => (is => 'rw', isa => 'HashRef');

my %FILECACHE;

sub is_dir {
 shift->entry->{type} eq 'tree'
}

sub is_submodule {
 shift->entry->{type} eq 'commit'
}

sub is_symlink {
 my $self = shift;
 $self->entry->{type} eq 'blob' &&
	$self->entry->{mode} eq '120000';
}

sub is_regular_file {
  my $self = shift;
  return !$self->is_dir && !$self->is_symlink && !$self->is_submodule;
}


sub BUILD {
 my $self = shift;

 my $entry = Gitlab::fetch_project_tree_entry($self->group,
		$self->project, $self->path);
 die "error fetching entry for $self" unless $entry;

 $self->entry($entry);
}

sub url {
  my $self = shift;
  my ($group, $project, $path) = ($self->group, $self->project, $self->path);
  return join('/', $group, $project, $path);
}

sub _has_file { return exists $FILECACHE{shift->url} }

sub _get_file {
  my $self = shift;
  my $url = $self->url;

  if (!$self->_has_file) {
    $FILECACHE{$url} = Gitlab::fetch_project_file($self->group,
      $self->project, $self->path);
  }

  return $FILECACHE{$url};
}

sub _fetch_file_names {
 my $self = shift;
 my $tree = Gitlab::fetch_project_tree($self->group, $self->project,
	$self->path);

 my @fnames = map { $_->{name} }  @{$tree};

 return @fnames;
}

sub _file_size {
  my $self = shift;
  return 0 unless $self->_has_file;

  return $self->_get_file->{size};
}

sub getattr {
 my $self = shift;

 # trigger the loading of file object
 $self->_get_file if $self->is_regular_file;

 main::make_getattr(
		size => $self->_file_size,
#		type => $self->type,
		mode => oct($self->entry->{mode}));
}


sub getdir {
	my $self = shift;
	return -POSIX::ENOENT() unless $self->is_dir;

	my @files = $self->_fetch_file_names();
		#### FsTree::getdir: \@files
	return (@files, 0);
}

sub open {
	my $self = shift;
	#### FsTree.open() : $self
	return -POSIX::EISDIR() if $self->is_dir;
	return 0;
}

sub read {
  my $self = shift;
  my ($buf, $off, $fh) = @_;
  #### FsTree.read() : $self, $buf, $off, $fh

  my $read = substr($self->_get_file->{content}, $off, $buf);
  #### FsTree.read() $read: $read

 return $read;
}

1;

package Gitlab;
use Moose;
use GitLab::API::v3;
use GitLab::API::v3::Constants qw( :all );
 use MIME::Base64;
our $API;

sub init {
	my ($url, $token) = @_;
	$API = GitLab::API::v3->new(
    	url   => $url,
    	token => $token,
 	);
}

sub fetch_project_file {
 my ($group, $project, $path, $ref) = @_;
 $ref //= 'master';

 die "bad empty filepath" if $path eq '';

 ### fetch_project_file:$group, $project, $path, $ref

 my $proj = fetch_project($group, $project);
 my $file = $API->file($proj->{id}, {file_path => $path, ref => $ref});

 $file->{content} = decode_base64($file->{content});
 delete $file->{encoding};

 return $file;
}

sub fetch_groups {
	$API->groups();
}

sub fetch_projects {
	my $projects = $API->all_projects();
}

sub fetch_project {
	my ($group, $project) = @_;
	my $projects = fetch_group_projects($group);

	my ($proj) = grep {$_->{name} eq $project} @$projects;

	return $proj;
}

sub fetch_group_projects {
	my $group = shift;
	my $res = $API->group($group);

	my $projs = $res->{projects};

	return $projs;
}

sub fetch_project_tree {
	my ($group, $project, $path) = @_;
	$path //= "";

	my $proj = fetch_project($group, $project);

	return $API->tree($proj->{id}, {path => $path});
}

sub fetch_project_tree_entry {
	my ($group, $project, $path) = @_;
	die "bad empty (tree) path" if ($path eq '');

	### fetch_project_tree_entry($group, $project, $path): $group, $project, $path

	$path =~ s|/$||;
	my @dirs = split qw(/), $path;
	my $filename = pop @dirs;
	my $parent = join('/', @dirs);

	#### $parent, $filename: $parent, $filename

	my $tree = fetch_project_tree($group, $project, $parent);
	return undef unless $tree;

	my ($entry) = grep { $_->{path} eq $path} @$tree;

	#### $entry: $entry
	return $entry if $entry;

	return undef;
}



1;

no Moose;
__PACKAGE__->meta->make_immutable;

package main;
$Carp::CarpLevel = 1;
use Smart::Comments -ENV;

use File::Basename;
use List::MoreUtils qw(uniq);
use Memoize;
use POSIX qw(ENOENT EISDIR EINVAL);
use English;
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

my $obj = FsObj->new(name => 'toto');
print $obj->size;

my ($mount_point) = @ARGV;
$mount_point ||= glob("~/.gitlabfs");

### using mount point: $mount_point
mkdir($mount_point) unless -e $mount_point;

$url   ||= $ENV{GITLAB_API_V3_URL};
$token ||= $ENV{GITLAB_API_V3_TOKEN};

pod2usage('give url and token') unless $url and $token;

Gitlab::init($url, $token);

memoize('dispatch');
memoize('Gitlab::fetch_groups');
memoize('Gitlab::fetch_projects');
memoize('Gitlab::fetch_project');
memoize('Gitlab::fetch_group_projects');
memoize('Gitlab::fetch_project_file');

sub is_dir_equal {
	my ($dir, $ref) = @_;

	$ref .= '/' unless $ref =~ m|/$|;
	$dir .= '/' unless $dir =~ m|/$|;

	return $ref eq $dir;
}


sub make_getattr {
	my %params = @_;

	$params{size} //= 0;
	$params{type} //= $DEFAULT_TYPE;
	$params{permissions} //= $DEFAULT_PERMISSIONS;
	$params{mode} //= $params{type} + $params{permissions};


	##### make_getattr %params: \%params
#
#           S_IFMT     0170000   bit mask for the file type bit fields
#           S_IFSOCK   0140000   socket
#           S_IFLNK    0120000   symbolic link
#           S_IFREG    0100000   regular file
#           S_IFBLK    0060000   block device
#           S_IFDIR    0040000   directory
#           S_IFCHR    0020000   character device
#           S_IFIFO    0010000   FIFO
#           S_ISUID    0004000   set-user-ID bit
#           S_ISGID    0002000   set-group-ID bit (see below)
#           S_ISVTX    0001000   sticky bit (see below)
#           S_IRWXU    00700     mask for file owner permissions
#           S_IRUSR    00400     owner has read permission
#           S_IWUSR    00200     owner has write permission
#           S_IXUSR    00100     owner has execute permission
#           S_IRWXG    00070     mask for group permissions
#           S_IRGRP    00040     group has read permission
#           S_IWGRP    00020     group has write permission
#           S_IXGRP    00010     group has execute permission
#           S_IRWXO    00007     mask for permissions for others (not in group)
#           S_IROTH    00004     others have read permission
#           S_IWOTH    00002     others have write permission
#           S_IXOTH    00001     others have execute permission


	#my $modes = $params{mode};

	my ($dev, $ino, $rdev, $blocks, $nlink, $blksize) = (0,0,0,1,1,$DEFAULT_BLOCKSIZE);
	my ($atime, $ctime, $mtime);
	$atime = $ctime = $mtime = time();

	return ($dev,$ino,$params{mode},$nlink,$UID,$GID,$rdev,$params{size},$atime,$mtime,$ctime,$blksize,$blocks);
}




sub dispatch {
    my $path = shift;
    ### dispatch $path: $path

	if (is_dir_equal($path, '/')) {
		return FsDir->new(name => '/', files => ['projects']);
	} elsif ($path =~  m|/projects|) {
		return dispatch_projects($path);
	} else {
		return FsObj->new();
	}
}

sub dispatch_projects {
    my $path = shift;
    ### dispatch_projects $path: $path
	return FsGroups->new(name => 'projects') if is_dir_equal($path, '/projects/');

	my ($u, $v, $group, $project, @treepath) = split qw(/), $path;

	return FsGroup->new(name => $group) if !defined $project;

	return FsProject->new(group => $group, name => $project)
		unless @treepath;

	my $treepath = join('/', @treepath);

	#### dispatch_projects FsTree: $group, $project, $treepath
	return FsTree->new(group => $group, project => $project, path => $treepath);
}


sub gfs_getattr {
 my $path = shift;
 ###  gfs_getattr: $path
 dispatch($path)->getattr();
}

sub gfs_getdir {
 my $path = shift;
 ###  gfs_getdir: $path
 dispatch($path)->getdir();
}

sub gfs_open {
  my $path = shift;
  ###  gfs_open: $path
	dispatch($path)->open();
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

sub gfs_read {
  my $path = shift;
  ###  gfs_read: $path, @_
  return dispatch($path)->read(@_);
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
use Fuse qw(fuse_get_context);
Fuse::main(
	mountpoint => $mount_point,
	getattr => "main::gfs_getattr",
	getdir => "main::gfs_getdir",
	open   => "main::gfs_open",
	statfs => "main::e_statfs",
	read   => "main::gfs_read",
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

