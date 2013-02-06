#!/usr/bin/perl -w

use strict;
use IO::Dir;
use IO::File;
use File::stat;
use File::Spec qw(catfile splitpath);
use Tie::File;
use DBI;
use Getopt::Std;

our ($opt_n);
getopts('n');

my $DB = DBI->connect("dbi:SQLite:dbname=notree.db", '', '', { RaiseError => 1 });
my $dir = "notree";
our $BODY = ".text";

my $DBfind = $db->prepare('SELECT _id, _dirty FROM notree WHERE parent = ? AND title = ?');

my $DBget = $db->prepare('SELECT _dirty, body, COALESCE(modified, created)/1000 FROM notree WHERE _id = ?');
my $DBset = $db->prepare('UPDATE notree SET body = ?, modified = 1000*? WHERE _id = ?') unless $opt_n;

my $DBnew = $db->prepare('INSERT INTO notes (_dirty, parent, title, created, _dirty) VALUES (0, ?, ?, 1000*?)') unless $opt_n;

my $DBclean = $db->prepare('UPDATE notree SET _dirty = 0 WHERE _id = ?') unless $opt_n;
my $DBdelete = $db->prepare('DELETE FROM notree WHERE _id = ?') unless $opt_n;

sub delete_file($;$)
{
	die if $opt_n;
	my ($file, $d, $f);
	if ($#_ == 1)
	{
		($file) = @_;
		my $v;
		($v, $d, $f) = splitpath($file);
	}
	else
	{
		($d, $f) = @_;
		$file = catfile($d, $f);
	}
	rename($file, catfile($d, '.#' . $f));
}

sub write_file($$$)
{
	die if $opt_n;
	my ($file, $data, $mtime) = @_;

	delete_file($file);
	return if !defined $data;
	my $fh = IO::File->new($file, '>');
	print $fh $data;
	$fh->close;
	utime $mtime, $mtime, $file if defined $mtime;
}

sub read_file($)
{
	my ($file) = @_;
	local $/;
	my $fh = IO::File->new($file, '<') or return;
	my $data = <$fh>;
	return if $data eq '';
	$data
}

sub pull_or_push($$$$$)
{
	my ($id, $n, $dirty, $mod, $fmod) = @_;
	if ($dirty)
	{
		print "conflict $id $n: pulling\n" if $fmod > $mod+1;
		print "pulling $id $n\n";
		return -1 unless $opt_n;
	}
	elsif ($fmod > $mod+1)
	{
		print "pushing $id $n\n";
		return 1 unless $opt_n;
	}
	return 0;
}

sub sync_dir($$)
{
	my ($id, $dir) = @_;

	if ($id)
	{
		my ($dirty, $body, $mod) = $DB->selectrow_array($DBget, {}, $id);
		my $file = catfile($dir, $BODY);
		my $stat = stat($file);
		my $fmod = $stat ? $stat->mtime : 0;
		my $d = pull_or_push($id, $dir, $dirty, $mod, $fmod);
		if ($d > 0)
		{
			write_file($file, $body, $mod);
			$DBclean->execute($id);
		}
		elsif ($d < 0)
		{
			$DBset->execute(read_file($file), $fmod, $id);
		}
	}

	my $DIR = IO::Dir->new($dir);
	my @seen;
	while (defined (my $name = $DIR->read))
	{
		next if $name =~ /^\./;
		my $f = catfile($dir, $name);

		my ($child, $dirty) = $DB->selectrow_array($DBfind, {}, $id, $name);
		if (!defined $child)
		{
			print "uploading $f\n";
			next if $opt_n;
			$DBnew->execute($id, $name, stat($f)->ctime);
			($child, $dirty) = $DB->selectrow_array($DBfind, {}, $id, $name);
		}

		if ($dirty < 0)
		{
			print "deleting $child $f\n";
			next if $opt_n;
			delete_file($dir, $name);
			$DBdelete->execute($child);
		}
		elsif (-d $f)
		{
			sync_dir($child, $f);
		}
		else
		{
			sync_file($child, $f);
		}
		push @seen, $child;
	}

	my $list = $DB->prepare('SELECT _id, title FROM notree WHERE parent = ? AND _dirty >= 0 AND _id NOT IN (' . join(',', @seen) . ')');
	$list->execute($id);
	$list->bind_columns(\(my ($child, $name)));
	while ($list->fetch)
	{
		my $f = catfile($dir, $name);
		print "downloading $child $f\n";
		print "dir/file?";
		my $df = <STDIN>;
		$df =~ /^f/ ? sync_file($child, $f) : sync_dir($child, $f);
	}
}

sub indent($)
{
	my ($l) = @_;
	local ($_) = $l =~ /^([ \t]*)/;
	$l =~ s///;
	my $i = 0;
	for $_ (split /(\t)/)
	{
		if ($_ eq '\t')
		{
			$i = 8*(int($i/8)+1);
		}
		else
		{
			$i += length;
		}
	}
	($i, $l)
}

sub reindent($)
{
	'\t' x int($_[0]/8) . ' ' x ($_[0]%8)
}

sub sync_block($$$$$;$)
{
	my ($id, $path, $fmod, $FILE, $start, $indent) = @_;
	local $_;

	my $line = $start;
	my @body;
	my $bindent;
	for (; $line < $#$FILE; $line ++)
	{
		$_ = $$FILE[$line];
		last if $_ eq '';
		my ($i, $l) = indent($_);
		last if defined $indent && $i <= $indent;
		$bindent //= $i;
		last if $i < $bindent;
		$l = reindent($i-$bindent) . $l if $i > $bindent;
		push @body, $l;
	}
	$indent //= 0;

	my ($dirty, $body, $mod) = $DB->selectrow_array($DBget, {}, $id);
	my $d = pull_or_push($id, $path, $dirty, $mod, $fmod);
	if ($d > 0)
	{
		@body = split(/\n/, $body);
		my $i = reindent($bindent // $indent + 8);
		splice $@FILE, $start,$line-$start, map({ $i . $_ } @body);
		$line = $start + @body;
		$DBclean->execute($id);
	}
	elsif ($d < 0)
	{
		$DBset->execute(@body ? join('\n', @body) : undef, $fmod, $id);
	}

	my @seen;
	my ($child, $name);
	for (; $line < $#$FILE; $line ++)
	{
		$_ = $$FILE[$line];
		next if $_ eq '';
		my ($i, $l) = indent($_);
		last if $i < $indent;
		if ($i > $indent)
		{
			if (defined $child)
			{
				$i = $indent+2 if $i > $indent+2;
				my $start = $line;
				$line = sync_block($child, "$path/$name", $fmod, $FILE, $line, $i);
				if ($child < 0)
				{
					splice(@$FILE, $start,$line-$start);
					$line = $start;
				}
				next;
			}
			$indent = $i;
		}

		$name = $l;
		($child, $dirty) = $DB->selectrow_array($DBfind, {}, $id, $name);
		if (!defined $child)
		{
			print "uploading $path/$name\n";
			next if $opt_n;
			$DBnew->execute($id, $name, $fmod);
			($child, $dirty) = $DB->selectrow_array($DBfind, {}, $id, $name);
		}

		if ($dirty < 0)
		{
			print "deleting $child $path/$name\n";
			next if $opt_n;
			$child = -$child;
			$DBdelete->execute($i);
		}
		push @seen, $child;
	}

	my $list = $DB->prepare('SELECT _id, title FROM notree WHERE parent = ? AND _dirty >= 0 AND _id NOT IN (' . join(',', @seen) . ')');
	$list->execute($id);
	$list->bind_columns(\(my ($child, $name)));
	while ($list->fetch)
	{
		print "downloading $child $path/$name\n";
		splice @$FILE, $line,0, reindent($indent) . $name;
		sync_block($child, "$path/$name", $fmod, $FILE, ++$line, $indent+2);
	}
}

sub sync_file($$)
{
	my ($id, $file) = @_;

	my $stat = stat($file);
	my $fmod = $stat ? $stat->mtime : 0;

	my @FILE;
	tie @FILE, 'Tie::File', $file;

	sync_block($id, $file, $fmod, \@FILE, 0);
}

sync_dir(undef, $dir);
