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
	'(https?:\/\/privatepaste\.com)\/([a-zA-Z0-9]+)'
	    => '"$1/download/$2"',
	'(https?:\/\/ideone\.com)\/([a-zA-Z0-9]+)'
	    => '"$1/plain/$2"',
	'(https?:\/\/www.ideone\.com)\/([a-zA-Z0-9]+)'
	    => '"$1/plain/$2"',
	'(https?:\/\/pastebin\.com)\/([a-zA-Z0-9]+)'
	    => '"$1/raw.php?i=$2"',
	'(https?:\/\/codepad\.org)\/([a-zA-Z0-9]+)'
	    => '"$1/$2/raw.c"',
	'(https?:\/\/bpaste\.net)\/show\/([a-zA-Z0-9]+)'
	    => '"$1/raw/$2"',
	'(https?:\/\/dpaste\.com)\/([a-zA-Z0-9]+)'
	    => '"$1/$2.txt"',
	'(https?:\/\/pastie\.org)\/([a-zA-Z0-9]+)'
	    => '"$1/pastes/$2/download"',
	'(https?:\/\/paste\.debian\.net)\/([a-zA-Z0-9]+)\/?'
	    => '"$1/download/$2"',
	'(https?:\/\/paste\.fedoraproject\.org)\/([a-zA-Z0-9]+)\/([a-zA-Z0-9]+)\/?'
	    => '"$1/$2/$3/raw/"',
	'(https?:\/\/sprunge\.us\/[a-zA-Z0-9]+)'
	    => '"$1"',
	'(https?:\/\/hastebin\.com)\/([a-zA-Z0-9]+).hs'
	    => '"$1/raw/$2"',
	'(https?:\/\/lpaste\.net)\/([a-zA-Z0-9]+)'
	    => '"$1/raw/$1"',
	'(https?:\/\/fpaste\.org)\/([a-zA-Z0-9]+)\/([a-zA-Z0-9]+)\/'
	    => '"$1/$2/$3/raw/"',
	'(https?:\/\/ghostbin\.com)\/paste\/([a-zA-Z0-9]+)'
	    => '"$1/paste/$2/raw"',
	'(https?:\/\/dpaste\.de)\/([a-zA-Z0-9]+)'
	    => '"$1/$2/raw"',
	'(https?:\/\/codeviewer\.org)\/view\/([a-zA-Z0-9:]+)'
	    => '"$1/download/$2"',
	'(https?:\/\/paste\.ee)\/p\/([a-zA-Z0-9]+)'
	    => '"$1/r/$2"',
	'(https?:\/\/paste\.linuxassist\.net)\/view\/([a-zA-Z0-9]+)'
	    => '"$1/view/raw/$2"',
	'(https?:\/\/paste\.pound-python\.org)\/show\/([a-zA-Z0-9]+)\/'
	    => '"$1/raw/$2/"',
	'(https?:\/\/pastebin\.geany\.org)\/([a-zA-Z0-9]+)\/'
	    => '"$1/$2/raw/"',
	'(https?:\/\/paste\.kde\.org)\/([a-zA-Z0-9]+)'
	    => '"$1/$2/uddsfq/raw"', #instead of 'uddsfq', any token seems to work (but not none!)
	'(https?:\/\/paste\.eientei\.org)\/show\/([a-zA-Z0-9]+)\/'
	    => '"$1/raw/$2/"',
	'(https?:\/\/www\.heypasteit\.com)\/clip\/([a-zA-Z0-9]+)'
	    => '"$1/download/$2"',
	'(https?:\/\/pastebin\.mozilla\.org)\/([a-zA-Z0-9]+)'
	    => '"$1/?dl=$2"',
	'(https?:\/\/paste\.ubuntu\.org\.cn)\/([a-zA-Z0-9]+)'
	    => '"$1/d$2"',
	'(https?:\/\/paste\.lugons\.org)\/show\/([a-zA-Z0-9]+)\/'
	    => '"$1/raw/$2/"'
);

# these would require scraping; most don't offer
# a mechanism for raw download at all
my @crapbins = (
	'https?:\/\/www\.pasteall\.org\/',
	'https?:\/\/paste2\.org\/',
	'https?:\/\/codepaste\.net\/',
	'https?:\/\/vpaste\.net\/',
	'https?:\/\/pastee\.org\/',
	'https?:\/\/paste\.jhvisser\.com\/',
	'https?:\/\/paste\.awesom\.eu\/',
	'https?:\/\/pastebin\.fr\/',
	'https?:\/\/paste\.ofcode\.org\/'
);

# these are equally shitty, but commonly used enough
# to justify scraping them. later, the FQDN is extracted
# (hence the capture group) and a script called
# scrape_FQDN.sh is attempted to run
my @scrapebins = (
	'https?:\/\/(pastebin\.ubuntu\.com)\/[a-zA-Z0-9]+',
	'https?:\/\/(paste\.ubuntu\.com)\/[a-zA-Z0-9]+'
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
my $nextmock = 0;
my $mockint = 3600;

my $repourl = "http://github.com/fstd/cwarn";

my $lastfull = '';
my $lastnick = '';
my $lastsubstandard = '';

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

	foreach my $rxp (@scrapebins) {
		$msg =~ /($rxp)/;
		next unless $1;
		my $capture = $1;
		if ($capture ne '' and $2 ne '') {
			my $fqdn = $2;
			my @out = `scrape_$fqdn.sh "$capture" >scraped.c`;
			next if (${^CHILD_ERROR_NATIVE} != 0);
			return "file://scraped.c";
		}
	}

	if ($msg =~ /http/) {
		say "possibly unhandled pastebin in msg '$msg'";
	}

	return '';
}

sub
Mock
{
	if (time > $nextmock) {
		IRCPrint("PRIVMSG $_[0] :\x01ACTION mocks $_[1] for using a substandard paste site.\x01");
		$nextmock = time + $mockint; #don't mock too often...
	}
}


$sck = IRCConnect($srv, $port, $pass, $mynick, $myuname, $myfname);

IRCPrint("NAMES #fstd"); #work around what appears to be a freenode glitch...
my $jointime = time + 5;

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
		my @cmdtok = split /  */, $tok[3];
		my $an = AdjNoun($iadjfile, $inounfile);
		if ($cmdtok[1] eq 'help' or $cmdtok[1] eq 'info') {
			IRCPrint("PRIVMSG $chan :$nick: RTFS, you $an: $repourl");
		}

		next;
	} elsif ($tok[3] =~ /^rau\?/) {
		if ($lastfull) {
			my $add = $lastsubstandard ? ' substandard' : '';
			IRCPrint("PRIVMSG $chan :Possible problems with $lastnick"
				."'s$add paste: $lastfull");
		} else {
			my $an = AdjNoun($iadjfile, $inounfile);
			IRCPrint("PRIVMSG $chan :No, you $an.");
		}
	}

	my $mocked = 0;
	foreach my $rxp (@crapbins) {
		if ($tok[3] =~ /$rxp/) {
			Mock $chan, $nick;
			$mocked = 1;
			last;
		}
	}

	if ($mocked == 1) {
		say "mocked -- next!";
		next;
	}

	my $pasteurl = GetPasteURL $tok[3];
	next if ($pasteurl eq '');

	my $substandard = ($pasteurl =~ /^file:/);
	my $garbage = 0;

	say "what about '$pasteurl' ($substandard)?";
	my @out = `cid.sh -vvv "$pasteurl" "in_garbage.c"`;

	chop $out[0];
	my @toks = split ' ', $out[0];

	if ($toks[0] eq 'BAD') {
		say "bad ($toks[1]) -- next!";
		next;
	} elsif ($toks[0] eq 'GARBAGE') {
		# we treat garbage as c99, basically just so we can still
		# manually query the results, in case it was actually
		# supposed to be C
		say 'cid.sh found this to be GARBAGE';
		$garbage = 1;
		$toks[0] = 'c99';
	} elsif ($toks[0] eq 'DUNNO') {
		say 'cid.sh failed to identify this; assuming c99';
		$toks[0] = 'c99';
	}

	my $nocomplain = ($garbage or $toks[1] eq 'NOMAIN');

	@out = `cwarn.sh -vvv -c "$toks[0]" -s "$slaves" "in_garbage.c"`;
	if (${^CHILD_ERROR_NATIVE} != 0) {
		IRCPrint("PRIVMSG $chan :\x01ACTION twitches involuntarily.\x01") unless $nocomplain;
		say 'cwarn failed -- next!';
		next;
	}
	#print STDERR Dumper(\@out);
	my $aref;
	my $aind;
	my $count = 0;
	my %res = ('OKAY' => [], 'NOCOMPILE' => [], 'WARNEDC' => [], 'NOLINK' => [], 'WARNEDL' => []);
	my $pone = '';
	my $pall = '';
	foreach my $ln (@out) {
		chop $ln;
		say "line is '$ln'";
		if ($ln =~ /^BEGIN/) {
			$count++;
			my @arr = split ' ', $ln;

			$aref = $res{$arr[1]};
			$aind = @{ $aref };
			shift @arr;
			$pall .= join(' ', @arr);
			shift @arr;
			@{ $aref }[$aind] = join ' ', @arr;
		} elsif ($ln =~ /^END/) {
			$pall .= "\n\n";
		} else {
			@{ $aref }[$aind] .= ($ln =~ s/^DATA /\n/r);
			$pall .= ($ln =~ s/^DATA /\n/r);
		}
	}

	print STDERR Dumper(\%res);

	my $origprog = "\n\n\n------------------------------------------------------------------------\n";
	$origprog .= "Original program was:\n\n";

	open my $handle, '<', 'in_garbage.c';
	my @lines = <$handle>;

	my $lc = 0;
	foreach my $ln (@lines) {
		$lc++;
		$origprog .= $lc . "\t" . $ln;
	}

	close $handle;
	$origprog .= "\n------------------------------------------------------------------------\n";

	$pall .= $origprog;
	open $handle, '>', 'paste_garbage.c';
	print $handle "$pall";
	close $handle;


	@out = `curl -s -F 'sprunge=<-' http://sprunge.us <paste_garbage.c`;
	$pall = $out[0];
	chop $pall;

	IRCPrint("PRIVMSG #fstd :$pall"); # XXX temporarily monitoring this

	$lastfull=$pall;
	$lastnick=$nick;
	$lastsubstandard = $substandard;

	if ($count == @{ $res{'OKAY'} }) {
		if (!$nocomplain and !$substandard) {
			IRCPrint("PRIVMSG $chan :\x01ACTION beams at $nick.\x01");
		} elsif ($substandard) { 
			IRCPrint("PRIVMSG $chan :\x01ACTION beams at $nick while cursing their poor choice of paste sites.\x01");
		}
		say "nothing to complain about - next!";
		next;
	}

	if (@{ $res{'OKAY'} }) {
		Mock $chan, $nick if $substandard;
		say "well it built /somewhere/ without issues... - next!";
		next;
	}

	if (@{ $res{'NOCOMPILE'} } + @{ $res{'WARNEDC'} } == 0) {
		#don't be overly pedantic wrt. to link errors
		Mock $chan, $nick if $substandard;
		say "this at least compiled everywhere (but failed to link somewhere) -- next";
		next;
	}

	my $max = -1;
	my $maxcand;
	my $maxtype;
	my $insult = 0; #insult when it doesn't even compile, don't insult when it only generates warnings
	foreach my $cand (@{ $res{'NOCOMPILE'} }) {
		# oh well this is bad.
		my @tmp = split '\n', $cand;
		if (@tmp > $max) {
			$max = @tmp;
			$maxcand = $cand;
			$maxtype = 'NOCOMPILE';
			$insult = 1;
		}
		
	}

	if ($max == -1) {
		foreach my $cand (@{ $res{'WARNEDC'} }) {
			# oh well this is bad.
			my @tmp = split '\n', $cand;
			if (@tmp > $max) {
				$max = @tmp;
				$maxcand = $cand;
				$maxtype = 'WARNEDC';
			}
			
		}
	}

	if ($max == -1) {
		say "wot -- next";
		next;
	}

	$pone = $maxtype . ' ' . $maxcand . $origprog;
	open $handle, '>', 'paste_garbage.c';
	print $handle "$pone";
	close $handle;

	@out = `curl -s -F 'sprunge=<-' http://sprunge.us <paste_garbage.c`;
	$pone = $out[0];
	chop $pone;

	if (!$nocomplain) {
		my $add = '';
		if ($insult) {
			my $an = AdjNoun($iadjfile, $inounfile);
			$add = ", you $an";
		}
		my $addbin = $substandard ? ' find a non-horrible paste site and then' : '';
		IRCPrint("PRIVMSG $chan :$nick: Please$addbin address the following problems$add: $pone");
		IRCPrint("PRIVMSG #fstd :fstd: $pone (full: $pall) [$nick]"); # XXX temporarily monitoring this
	} elsif ($substandard) {
		Mock $chan, $nick;
	} else {
		say "unfortunately, we're not complaining..."
	}
}
