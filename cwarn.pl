#!/usr/bin/env perl

#2015, Timo Buhrmester
#complain about bad testcases; work in progress

use strict;
use warnings;
use v5.10;

use IO::Socket;
use IO::Select;
use Socket qw(SOCK_STREAM getaddrinfo);
use Data::Dumper;

# mappings from commonly pasted pastebins to their respective raw URL
# the double quotes are required because we /ee the substitution
my %bins = (
	'(https?:\/\/ideone\.com)\/([a-zA-Z0-9]+)'
	    => '"$1/plain/$2"',
	'(https?:\/\/pastebin\.com)\/([a-zA-Z0-9]+)'
	    => '"$1\/raw.php?i=$2"',
	'(https?:\/\/codepad\.org)\/([a-zA-Z0-9]+)'
	    => '"$1\/$2\/raw.c"',
	'(https?:\/\/bpaste\.net)\/show\/([a-zA-Z0-9]+)'
	    => '"$1\/raw\/$2"',
	'(https?:\/\/dpaste\.com)\/([a-zA-Z0-9]+)'
	    => '"$1\/$2.txt"',
	'(https?:\/\/pastie\.org)\/([a-zA-Z0-9]+)'
	    => '"$1\/pastes\/$2\/download"',
	'(https?:\/\/paste\.debian\.net)\/([a-zA-Z0-9]+)\/?'
	    => '"$1\/download\/$2"',
	'(https?:\/\/paste\.fedoraproject\.org)\/([a-zA-Z0-9]+)\/([a-zA-Z0-9]+)\/?'
	    => '"$1\/$2\/$3\/raw\/"',
);

my $slaves = '/home/fstd/prj/cwarn/slaves';

my $iadjfile = "insadj"; #path to file with one adjective per line
my $inounfile = "insnoun"; #path to file with one noun per line

my $srv = "irc.freenode.org";
my $port = 6667;
my $pass = "secret";
my $mynick = "rau";
my $myuname = "rau";
my $myfname = "rau reloaded";

my $read_timeout = 10;
my $joinchunk = 40;
my $joininterval = 1;
my $hbinterval = 60;
my $nexthb = time + 10;

my $repourl = "http://github.com/fstd/cwarn";

my $lastfull = '';

#my %chans = ('##c' => 1, '#fstd' => 1);
my %chans = ('#fstd' => 1);

my $sck;
my $sel = IO::Select->new();



# resolve, connect and log on to IRC server
sub
IRCConnect
{
	my ($host, $port, $pass, $nick, $uname, $fname) = @_;
	say "resolving...";
	my ($err, @res) = getaddrinfo($host, $port, {socktype => SOCK_STREAM});
	die "getaddrinfo() failed" if $err;
	say "resolved!";

	foreach my $ai (@res) {
		my $cand = IO::Socket->new();
		$cand->socket($ai->{family}, $ai->{socktype}, $ai->{protocol})
			or next;

		$cand->connect($ai->{addr})
			or next;

		$sck = $cand;
		$sck->timeout(2);
		last;
	}

	die "connect() failed" unless $sck;
	say "connected!";

	IRCPrint("PASS $pass") if $pass;
	IRCPrint("NICK $nick");
	IRCPrint("USER $uname 8 * :$fname");

	while (my $line = IRCRead($read_timeout)) {
		say time."\tREAD\t'". $line =~ s/\x0D?\x0A$//r ."'";
		my @tok = Tokenize($line);
		if ($tok[1] eq "001") {
			say "logged on \\o/";
			last;
		} elsif ($tok[1] eq "PING") {
			IRCPrint("PONG :$tok[2]");
		} elsif ($tok[1] eq "432" # various messgaes indicating
		    or $tok[1] eq "433"   # that we need to change nick
		    or $tok[1] eq "436"
		    or $tok[1] eq "437") {
			IRCPrint("NICK ${nick}_");
		}
	}

	return $sck;
}

sub
IRCRead
{
    $sel->add($sck);
    if (!!$sel->can_read($_[0])) {
	return <$sck>;
    }

    return "T"; #meh.
}

sub
IRCPrint
{
	print $sck $_[0]."\r\n";
	say time."\tWRITE\t'$_[0]'";
}

# parse IRC protocol message into array of parameters; return that array.
# first element will be the prefix, if present; command and arguments (if
# present) follow in subsequent elements (i.e. [1] will always be the `command')
sub
Tokenize
{
	my $line = $_[0] =~ s/\x0D?\x0A$//r;
	my @spl = split(" ", $line);

	my @tok;
	$tok[0] = substr(shift(@spl), 1) if ($line =~ /^:/);

	my $i = 1;
	while (my $t = shift(@spl)) {
		if ($t =~ /^:/) {
			$tok[$i++] = substr($t, 1)." ".join(" ", @spl);
			last;
		}
		$tok[$i++] = $t;
	}

	return @tok;
}


# concatenate %hash's keys, separate by $delim
sub
JoinHashKeys
{
	my ($delim, %hash) = @_;
	my $res;
	my $first = 1;
	foreach my $chan (keys %hash) {
		$res .= $delim unless $first;
		$first = 0;
		$res .= $chan;
	}

	return $res;
}


# generate insult;  read files every time so we can add words on the fly
sub
AdjNoun
{
	my ($afile, $nfile) = @_;
	open FILE, "<$afile" or die "Could not open $afile: $!\n";
	my @array = <FILE>;
	close FILE;
	my $adj = $array[rand @array] =~ s/\x0D?\x0A$//r;

	open FILE, "<$nfile" or die "Could not open $nfile: $!\n";
	@array = <FILE>;
	close FILE;
	my $noun = $array[rand @array] =~ s/\x0D?\x0A$//r;
	
	return "$adj $noun";
}


sub
GetPasteURL
{
	my $msg = $_[0];
	foreach my $rxp (keys %bins) {
		$msg =~ /($rxp)/;
		next unless $1;
		my $capture = $1;
		if ($capture ne '') {
			my $subst = $bins{$rxp};
			my $raw = $capture =~ s/$rxp/$subst/eer;
			return $raw;
		}
	}

	if ($msg =~ /http/) {
		say "possibly unhandled pastebin in msg '$msg'";
	}
	
	return '';
}


$sck = IRCConnect($srv, $port, $pass, $mynick, $myuname, $myfname);

IRCPrint("NAMES #fstd"); #work around what appears to be a freenode glitch...
my $jointime = time;

my @joinarr;
foreach my $chan (keys %chans) {
	push(@joinarr, $chan);
}

while (my $line = IRCRead($read_timeout)) {
	say time."\tREAD\t'". $line =~ s/\x0D?\x0A$//r ."'" unless $line eq "T";
	my @tok = Tokenize($line);
	IRCPrint("PONG :$tok[2]") if ($tok[1] eq "PING");
	if ($tok[1] eq "T") {
		if (time >= $nexthb) {
			$nexthb = time + $hbinterval;
			IRCPrint("PING :foo");
		}
	}

	if ($tok[1] eq "404") {
		IRCPrint("PART $tok[3]");
		IRCPrint("PRIVMSG fstd :fstd: left $tok[3]")
	}

	if ($tok[1] eq "KICK" and $tok[3] eq $mynick) {
		IRCPrint("PRIVMSG fstd :fstd: kicked from $tok[2]");
	}

	if (time >= $jointime and @joinarr) {
		my $n = $joinchunk;
		my $chstr;
		my $ch;
		while ($n-- && ($ch = shift @joinarr)) {
			$chstr .= "$ch,";
		}
		chop $chstr if $chstr;

		IRCPrint("JOIN $chstr");
		$jointime = time + $joininterval;
	}

	next unless ($tok[1] eq "PRIVMSG");

	my $nick = (split("!", $tok[0]))[0];

	unless ($chans{lc($tok[2])}) {
		say "none of my chans - next!";
		next;
	}

	my $chan = lc($tok[2]);

	if ($tok[3] =~ /^rau: /) {
		say "yes";
		my @cmdtok = split /  */, $tok[3];
		if ($cmdtok[1] eq 'help' or $cmdtok[1] eq 'info') {
			IRCPrint("PRIVMSG $chan :$nick: RTFS $repourl");
		} elsif ($cmdtok[1] eq 'paste' or $cmdtok[1] eq 'geif') {
			my $an = AdjNoun($iadjfile, $inounfile);
			IRCPrint("PRIVMSG $chan :$nick: $lastfull, you $an.");
		}

		next;
	}

	my $pasteurl = GetPasteURL $tok[3];

	next if ($pasteurl eq '');

	say "what about '$pasteurl'?";
	my @out = `cwarn.sh -vvv -s "$slaves" "$pasteurl"`;
	if (${^CHILD_ERROR_NATIVE} != 0) {
		IRCPrint("PRIVMSG $chan :\x01ACTION twitches involuntarily.\x01");
		say 'cwarn failed -- next!';
		next;
	}
	print STDERR Dumper(\@out);

	if (@out == 1) {
		#IRCPrint("PRIVMSG $chan :\x01ACTION beams.\x01");
		say "nothing to complain about - next!";
		$lastfull=$out[0];
		next;
	}

	if (@out != 2) {
		IRCPrint("PRIVMSG $chan :\x01ACTION drools.\x01");
		say "huh? - next";
		next;
	}

	chop $out[0]; chop $out[1];
	$lastfull=$out[1];

	my $an = AdjNoun($iadjfile, $inounfile);
	IRCPrint("PRIVMSG $chan :$nick: Please address the the following problems, you $an: $out[0]");
}