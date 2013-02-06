#!/usr/bin/perl -w

use strict;
use IO::Dir;
use IO::File;
use File::stat;
use File::Spec::Functions qw(catfile splitpath);
use Tie::File;
use DBI;
use Getopt::Std;

our ($opt_n, $opt_d, $opt_f) = (0, 0, 0);
getopts('ndf');

my $DB = DBI->connect("dbi:SQLite:dbname=notree.db", '', '', { RaiseError => 1 });
my $dir = "notree";
our $BODY = ".text";

my $DBfind = $DB->prepare('SELECT _id, _dirty FROM notree WHERE parent = ? AND title = ?');

my $DBget = $DB->prepare('SELECT _dirty, body, COALESCE(modified,0)/1000 FROM notree WHERE _id = ?');
my $DBset = $DB->prepare('UPDATE notree SET body = ?, modified = 1000*? WHERE _id = ?') unless $opt_n;

my $DBnew = $DB->prepare('INSERT INTO notree (_dirty, parent, title, created) VALUES (0, ?, ?, 1000*?)') unless $opt_n;

my $DBclean = $DB->prepare('UPDATE notree SET _dirty = 0 WHERE _id = ?') unless $opt_n;
my $DBdelete = $DB->prepare('DELETE FROM notree WHERE _id = ?') unless $opt_n;

sub delete_file($;$)
{
	die if $opt_n;
	my ($file, $d, $f);
	if ($#_ == 0)
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
	my $fh = IO::File->new($file, '<') or return undef;
	my $data = <$fh>;
	return undef if $data eq '';
	$data
}

sub pull_or_push($$$$$)
{
	my ($id, $n, $dirty, $mod, $fmod) = @_;
	print "compare $id $n $dirty $mod $fmod\n" if $opt_d >= 2;
	if ($dirty || $fmod == 0)
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

sub indent($)
{
	my ($l) = @_;
	local ($_) = $l =~ /^([ \t]*)/;
	$l =~ s///;
	my $i = 0;
	for $_ (split /(\t)/)
	{
		if ($_ eq "\t")
		{
			$i = 8*(int($i/8)+1);
		}
		else
		{
			$i += length;
		}
	}
	wantarray ? ($i, $l) : $i
}

sub reindent($)
{
	"\t" x int($_[0]/8) . ' ' x ($_[0]%8)
}

sub sync_block($$$$$;$)
{
	my ($id, $path, $fmod, $FILE, $start, $indent) = @_;
	print "sync_block $id $path $start $indent\n" if $opt_d;
	local $_;

	my $line = $start;
	my @body;
	my $bindent;
	for (; $line <= $#$FILE; $line ++)
	{
		$_ = $$FILE[$line];
		my ($i, $l) = indent($_);
		last if $l eq '' or defined $indent && $i <= $indent;
		$bindent //= $i;
		last if $i < $bindent;
		$l = reindent($i-$bindent) . $l if $i > $bindent;
		push @body, $l;
		print "body $id $path $line: $_\n" if $opt_d >= 2;
	}
	$bindent //= defined $indent ? $indent + 8 : 0;
	$indent //= 0;

	my ($dirty, $body, $mod) = $DB->selectrow_array($DBget, {}, $id);
	my $d = pull_or_push($id, $path, $dirty, $mod, $fmod);
	if ($d < 0)
	{
		@body = split(/\n/, $body);
		my $i = reindent($bindent);
		splice @$FILE, $start,$line-$start, map({ $i . $_ } @body);
		$line = $start + @body;
		$DBclean->execute($id);
	}
	elsif ($d > 0)
	{
		$DBset->execute(@body ? join("\n", @body) : undef, $fmod, $id);
		$mod = $fmod;
	}

	print "begin $id $path $line: $indent,$bindent\n" if $opt_d >= 2;

	if ($line <= $#$FILE && $$FILE[$line] eq '')
	{
		$line++;
	}
	elsif ($bindent == $indent)
	{
		splice @$FILE, $line++,0, '';
	}

	my @seen;
	while ($line <= $#$FILE)
	{
		$_ = $$FILE[$line];
		my ($i, $l) = indent($_);
		last if $i < $indent;
		$indent = $i if $i > $indent;

		print "item $id $path $line: $_\n" if $opt_d >= 2;
		my $name = $l;
		my ($child, $dirty) = $DB->selectrow_array($DBfind, {}, $id, $name);
		if (!defined $child)
		{
			print "uploading $path/$name\n";
			$DBnew->execute($id, $name, $fmod) unless $opt_n;
			($child, $dirty) = $DB->selectrow_array($DBfind, {}, $id, $name);
		}

		if ($dirty < 0)
		{
			print "deleting $child $path/$name\n";
			$DBdelete->execute($child) unless $opt_n;
			# FIXME: children get reuploaded!
		}

		my $m;
		my $start = $line;
		($line, $m) = sync_block($child, "$path/$name", $fmod, $FILE, $line+1, $i+2);
		$mod = $m if $m > $mod;

		if ($dirty < 0 && !$opt_n)
		{
			splice @$FILE, $start,$line-$start;
			$line = $start;
		}

		push @seen, $child;
	}

	if ($opt_f)
	{
		$DB->do('UPDATE notree SET _dirty = -1 WHERE parent = ? AND _dirty >= 0 AND _id NOT IN (' . join(',', @seen) . ')', {}, $id);
	}
	else
	{
		my $list = $DB->prepare('SELECT _id, title FROM notree WHERE parent = ? AND _dirty >= 0 AND _id NOT IN (' . join(',', @seen) . ')');
		$list->execute($id);
		$list->bind_columns(\(my ($child, $name)));
		while ($list->fetch)
		{
			print "downloading $child $path/$name\n";
			splice @$FILE, $line,0, reindent($indent) . $name;
			my $m;
			($line, $m) = sync_block($child, "$path/$name", 0, $FILE, $line+1, $indent+2);
			$mod = $m if $m > $mod;
		}
	}
	wantarray ? ($line, $mod) : $mod;
}

sub sync_file($$)
{
	my ($id, $file) = @_;
	print "sync_file $id $file\n" if $opt_d;

	my $stat = stat($file);
	my $fmod = $stat ? $stat->mtime : 0;

	my @FILE;
	tie @FILE, 'Tie::File', $file;
	my $mod = sync_block($id, $file, $fmod, \@FILE, 0);
	untie @FILE;
	utime $mod, $mod, $file;
}

sub sync_dir($$)
{
	my ($id, $dir) = @_;
	print "sync_dir $id $dir\n" if $opt_d;

	if ($id)
	{
		my ($dirty, $body, $mod) = $DB->selectrow_array($DBget, {}, $id);
		my $file = catfile($dir, $BODY);
		my $stat = stat($file);
		my $fmod = $stat ? $stat->mtime : 0;
		my $d = pull_or_push($id, $dir, $dirty, $mod, $fmod);
		if ($d < 0)
		{
			write_file($file, $body, $mod);
			$DBclean->execute($id);
		}
		elsif ($d > 0)
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

	if ($opt_f)
	{
		$DB->do('UPDATE notree SET _dirty = -1 WHERE parent = ? AND _dirty >= 0 AND _id NOT IN (' . join(',', @seen) . ')', {}, $id);
	}
	else
	{
		my $list = $DB->prepare('SELECT _id, title FROM notree WHERE parent = ? AND _dirty >= 0 AND _id NOT IN (' . join(',', @seen) . ')');
		$list->execute($id);
		$list->bind_columns(\(my ($child, $name)));
		while ($list->fetch)
		{
			my $f = catfile($dir, $name);
			print "downloading $child $f\n";
			print "dir/file?";
			my $df = <STDIN>;
			if ($df =~ /^f/)
			{
				sync_file($child, $f);
			}
			else
			{
				mkdir($f);
				sync_dir($child, $f);
			}
		}
	}
}

sync_dir(0, $dir);
