#!/usr/bin/env perl

#2015, Timo Buhrmester
#complain about bad testcases; work in progress

#pastes are not distinguished by channel

use strict;
use warnings;
use v5.10;

use IO::Socket;
use IO::Select;
use Socket qw(SOCK_STREAM getaddrinfo);
use Data::Dumper;
use POSIX 'strftime';

my $iadjfile = "insadj"; #path to file with one adjective per line
my $inounfile = "insnoun"; #path to file with one noun per line

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
	'(https?:\/\/paste\.pr0\.tips\/[a-zA-Z0-9]+)'
	    => '"$1"',
	'(https?:\/\/vp\.dav1d\.de\/[a-zA-Z0-9]+)'
	    => '"$1"',
	'(https?:\/\/sprunge\.us\/[a-zA-Z0-9]+)'
	    => '"$1"',
	'(https?:\/\/hastebin\.com)\/([a-zA-Z0-9]+).hs'
	    => '"$1/raw/$2"',
	'(https?:\/\/lpaste\.net)\/([a-zA-Z0-9]+)'
	    => '"$1/raw/$2"',
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
	'(https?:\/\/pastebin\.ca)\/([a-zA-Z0-9]+)'
	    => '"$1/raw/$2"',
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
	'https?:\/\/paste\.ofcode\.org\/',
	#the following are scraped (see below) but included here for mocking purposes
	'https?:\/\/pastebin\.ubuntu\.com\/',
	'https?:\/\/paste\.ubuntu\.com\/'
);

# these are equally shitty, but commonly used enough
# to justify scraping them. later, the FQDN is extracted
# (hence the capture group) and a script called
# scrape_FQDN.sh is attempted to run
my @scrapebins = (
	#'https?:\/\/(gist\.github\.com)\/(?:[^/]+\/)?[a-fA-F0-9]+',
	'https?:\/\/(pastebin\.ubuntu\.com)\/[a-zA-Z0-9]+',
	'https?:\/\/(paste\.ubuntu\.com)\/[a-zA-Z0-9]+'
);

# these are supposed to eventually be overridable by command line switches
my $mysrv = "irc.freenode.org:6667";
my $mypass = "secret";
my $mynick = "rau";
my $myuname = "rau";
my $myfname = "rau reloaded";
#my $mychans = '#hutzelbrutzel';
my $mychans = '##c,#hutzelbrutzel';
my $monchan = '#hutzelbrutzel';
my $read_timeout = 10;
my $verbose = 2;

my $sck;
my %mocked;
my $mockint = 5;

#original URLs of seen pastes, in case someone quotes a paste
my %seen;

my $prgnam = $0 =~ s/^.*\///r;

# indentations shows call hierarchy
sub session;
  sub handle_chanmsg;
    sub do_paste;
      sub get_paste_url;
      sub repaste;
      sub build_paste;
      sub store_paste;
    sub do_crapbins;
      sub mock;
    sub do_raucmd;
      sub parse_msg;
      sub retrieve_paste;

# and some helpers
sub irc_connect;
sub irc_read;
sub irc_print;
sub irc_tknz;
sub time_interval;
sub whose;
sub attrs;
sub see;
sub huh;
sub insult;


sub now { return strftime('%j %H:%M:%S', localtime); }
sub W { say STDERR "$prgnam: ".now.": ".($_[0] =~ s/[\r\n]/\$/grm); }
sub E { W "ERROR: $_[0]"; exit 1; }
sub D { W "DBG: $_[0]" if $verbose; }
sub V { W "DBG: $_[0]" if $verbose > 1; }
sub L { irc_print("PRIVMSG $monchan :$_[0]"); }

# notes:
# show a clean/indented version of a given paste
# show build info for a given paste
# build as <std>
# fork a paste, sed(1) it




sub session {
	my $sel = IO::Select->new();
	$sck = irc_connect($mysrv, $mypass, $mynick, $myuname, $myfname);
	if ($sck eq '') {
		W "Failed to connect/logon";
		return;
	}

	my $hbinterval = 60;
	my $nexthb = time + 10;

	$sel->add($sck);

	my %chans;
	$chans{lc($_)} = 1 foreach (split ',', $mychans);

	irc_print("JOIN $mychans");

	my $gotpong = 1;
	while (my $line = irc_read($sel, $read_timeout)) {
		my @tok = irc_tknz($line);
		if ($tok[1] eq "T") {
			if (time >= $nexthb) {
				if (!$gotpong) {
					W "ping timeout.";
					last;
				}

				$nexthb = time + $hbinterval;
				irc_print("PING :foo");
				$gotpong = 0;
			}
		}

		$gotpong = 1 if ($tok[1] eq "PONG");

		irc_print("PONG :$tok[2]") if ($tok[1] eq "PING");

		next unless ($tok[1] eq "PRIVMSG");

		unless ($chans{lc($tok[2])}) {
			D lc($tok[2])." is none of my chans - next!";
			next;
		}

		handle_chanmsg \@tok;
	}
}


sub handle_chanmsg {
	my ($tokref) = @_;

	my $nick = (split("!", $tokref->[0]))[0];
	my $chan = lc($tokref->[2]);
	my $msg = $tokref->[3];

	return if ($nick eq 'candide');

	D "<$nick:$chan> $msg";

	do_paste($nick, $chan, $msg);
	do_crapbins($nick, $chan, $msg);
	do_raucmd($nick, $chan, $msg);
}

sub twitches {
	my @arr = ('twitches', 'burps', 'stares', 'recoils', 'facepalms', 'sighs', 'rolls eyes', 'scratches head');
	return $arr[rand @arr];
}

sub do_paste {
	my ($nick, $chan, $msg) = @_;

	my ($url, $ourl) = get_paste_url $msg;
	return unless $url;
	return if exists $seen{$ourl};
	$seen{$ourl} = 1 unless $ourl =~ /ideone\.com/;

	my $substandard = $url =~ /^file:/;

	L "Hmm, a ".($substandard ? 'substandard ' : '')."paste! ('$ourl' -> '$url')";

	my ($status, $rpurl, $content) = repaste $url;
	if (not $rpurl) {
		irc_print("PRIVMSG $chan :\x01ACTION ".twitches."\x01");
		return;
	}

	my $p = { 'TIME' => time, 'NICK' => $nick, 'CHAN' => $chan, 'URL' => $rpurl, 'OURL' => $ourl, 'MSG' => $msg };

	if ($status eq 'noindent') {
		L "Could not indent(1) that...";
		$p->{'NOINDENT'} = 1;
	}

	my $buildout = build_paste($p, 'auto');

	if (!$buildout) {
		$buildout = "(couldn't build)";
		$p->{'NOBUILD'} = 1;
	}

	$p->{'FULLINFO'} = $buildout;

	my $fn = store_paste($p, $content);
	if (!$fn) {
		L "Failed to store that...";
		W "Failed to store:";
		print STDERR Dumper($p);
		return;
	}
}

sub do_crapbins {
	my ($nick, $chan, $msg) = @_;
	foreach my $rxp (@crapbins) {
		if ($msg =~ /$rxp/) {
			mock $chan, $nick;
			return;
		}
	}
}

sub do_raucmd {
	my ($nick, $chan, $msg) = @_;

	if ($msg =~ /^rau[:,!?]/) {
		$msg =~ s/^rau[:,!?] *//;
		$msg =~ s/[,.!?] *rau[?!1.]*$//; #trim off if present
	} elsif ($msg =~ /[,.!?] *rau[?!1.]*$/) {
		$msg =~ s/[,.!?] *rau[?!1.]*$//;
	} else {
		return;
	}

	my ($filnick, $filmsg, $n, $insverbs, $tell, $rest) = parse_msg $msg;


	my $pref = retrieve_paste($n, $filnick, '', $filmsg);

	my $add = '';
	$add = ', you '.insult($insverbs) if $insverbs >= 0; #-1 = not insulted


	W "RAUCMD: '$rest' (n: '$n', filnick: '$filnick', filmsg '$filmsg', ins: ($insverbs verbs))";
	my $crit = '';
	$crit .= "; nick: '$filnick'" if $filnick;
	$crit .= "; number: '$n'" if $n;
	$crit .= "; msg: '$filmsg'" if $filmsg;
	#$crit .= "; fulltext: '$filft'" if $filft;

	$crit =~ s/^; // if $crit;

	my $notfound = !scalar keys(%{$pref});
	#if (!scalar keys(%{$pref})) {
		#W "failed to retrieve paste$add: n: '$n', filnick: '$filnick', filmsg: '$filmsg'";
		#return;
	#}

	if ($tell eq 'offender') {
		$tell = $notfound ? '' : $pref->{'NICK'};
	}

	$tell = $nick unless $tell;

	my $ago;
	if (!$notfound) {
		$ago = time_interval($pref->{'TIME'})." ago";
	}

	#my $rxp = '\b(?:treat|build|compile) +as +[cC](89|90|99|11)\b';
	#if ($rest =~ /$rxp/) {
		#my $std = $1;
		##irc_print("PRIVMSG #hutzelbrutzel :Treating paste '$pref' as '$std'$add");
		#return;
	#}

	#$rxp = '\b(?:fork|modify|rewrite)\b[^:]*:(.*)$';
	#if ($rest =~ /$rxp/) {
		#my $sed = $1;
		##irc_print("PRIVMSG #hutzelbrutzel :Modifying paste '$pref' with '$sed'$add");
		#return;
	#}


	my $rxp = '\b(?:clean|cleanup|sanitize|indent|prett[yi]|(?:re-?paste)|deretard)\b';
	if ($rest =~ /$rxp/) {
		if ($notfound) {
			irc_print("PRIVMSG $chan :Couldn't dig up a paste with the mentioned criteria ($crit)");
		} else {
			my $what = exists $pref->{'NOINDENT'} ? 're-pasted (could not indent(1))' : 'sanitized';
			irc_print("PRIVMSG $chan :$tell: ".see." $pref->{'URL'}?c$add ($what ".whose($pref).attrs($pref)." code, pasted $ago at <$pref->{'OURL'}>)");
		}
		return;
	}

	$rxp = '\b(?:show|info|details|give|gib|let.s see)\b';
	if ($rest =~ /$rxp/) {
		if ($notfound) {
			irc_print("PRIVMSG $chan :Couldn't dig up a paste with the mentioned criteria ($crit)");
		} elsif (exists $pref->{'NOBUILD'}) {
			irc_print("PRIVMSG $chan :$nick: Sorry, for some reason, I couldn't build ".whose($pref).attrs($pref)." code (pasted $ago at <$pref->{'OURL'}>).  fstd?");
		} else {
			irc_print("PRIVMSG $chan :$tell: ".see." $pref->{'FULLINFO'}$add (full build info for ".whose($pref).attrs($pref)." code, pasted $ago at <$pref->{'OURL'}>)");
		}
		return;
	}


	L "Didn't understand '$rest'";
	irc_print("PRIVMSG $chan :".huh($nick));
}


sub parse_msg {
	my ($msg) = @_;
	my $rxp = '\b(?:with|said|wrote) +"([^"]+)"';
	my $filmsg = '';
	if ($msg =~ /$rxp/) {
		$filmsg = $1;
		$msg =~ s/$rxp//;
	}

	$rxp = '\b((?:[1-9][0-9]*)|fir|seco|thi|late)(?:st|nd|rd|th)( +to last)?';
	my $n = 0;
	if ($msg =~ /$rxp/) {
		$n = $1;
		$n =~ s/fir/1/;
		$n =~ s/late/1/;
		$n =~ s/seco/2/;
		$n =~ s/thi/3/;
		$n = $2 ? -$n : $n;
		$msg =~ s/$rxp//;
	}

	$rxp = '\b(?:of|from|by) +([][a-zA-Z0-9^_\\|`{}-]+)\b';
	my $filnick = '';
	if ($msg =~ /$rxp/) {
		$filnick = $1;
		$msg =~ s/$rxp//;
	}

	if (!$filnick) {
		$rxp = "\\b([][a-zA-Z0-9^_\\\\|`{}-]+)'s? (?:paste|(?:test ?case)|pastie|code)\\b";
		if ($msg =~ /$rxp/) {
			$filnick = $1;
			$msg =~ s/$rxp//;
		}
	}

	my $tell = '';
	$rxp = '\btell ((?:the [a-zA-Z-]+)|(?:[][a-zA-Z0-9^_\\|`{}-]+))\b';
	if ($msg =~ /$rxp/) {
		$tell = $1;
		$tell = 'offender' if $tell =~ /^the(m| )/;
		W "msg is '$msg'";
		$msg =~ s/$rxp//;
		W "msg now '$msg'";
	}

	my $word = "[a-zA-Z'-]+";
	$rxp = "(?:(?:, *)|\\b)(?:you|thou|u) +((?:$word(?:, *$word)* )?+$word)";
	my $insverbs = -1;
	my $ins = '';
	if ($msg =~ /$rxp/) {
		$ins = $1;
		$msg =~ s/$rxp//;
		my @tmp = split / +/, $ins;
		$insverbs = @tmp - 1;
	}

	$msg =~ s/[,.!?-]+//g;
	$msg =~ s/ +/ /g;
	$msg =~ s/^ //;
	$msg =~ s/ $//;

	$msg = 'show' unless $msg; #this allows us to say just "rau?"

	return ($filnick, $filmsg, $n, $insverbs, $tell, $msg);
}

sub get_paste_url {
	my $msg = $_[0];
	foreach my $rxp (keys %bins) {
		$msg =~ /($rxp)/;
		next unless $1;
		my $capture = $1;
		if ($capture ne '') {
			my $subst = $bins{$rxp};
			my $raw = $capture =~ s/$rxp/$subst/eer;
			D "'$capture' -> '$raw'";
			return ($raw, $capture);
		}
	}

	foreach my $rxp (@scrapebins) {
		$msg =~ /($rxp)/;
		next unless $1;
		my $capture = $1;
		if ($capture ne '' and $2 ne '') {
			my $fqdn = $2;
			# XXX breaks multiple instances in same $PWD
			D "Running: scrape_$fqdn.sh '$capture' >scraped.c";
			my @out = `scrape_$fqdn.sh '$capture' >scraped.c`;
			if (${^CHILD_ERROR_NATIVE} != 0) {
				W "failed to scrape '$capture'";
				next;
			}
			my $raw = "file://scraped.c";
			D "Scraped: '$capture' -> '$raw'";
			return ($raw, $capture);
		}
	}

	$msg =~ /(https?:\/\/[][a-zA-Z0-9.:-]+\/[^ ]+(?: |$))/;
	if ($1) {
		W "Dunno: '$1' -> ???";
	}

	return ('', '');
}

sub repaste {
	my ($url) = @_;

	D "Running: repaste.sh '$url'";
	my @out = `repaste.sh '$url'`;
	my $ret = $? >> 8;

	#exits with 2 if (just) indent(1) failed (due to syntax errors or so)
	if ($ret != 0 and $ret != 2) {
		W "Failed to repaste '$url': $ret";
		L "Failed to repaste '$url': $ret";
		return ('', '', '');
	}

	chop $out[0];

	my @r = split ' ', $out[0];

	open my $handle, '<', $r[1];
	my @lines = <$handle>;
	close $handle;
	my $content = join '', @lines;

	my $s = $ret == 2 ? 'noindent' : '';
	D "Repasted '$url' as '$out[0]'";
	return ($s, $r[0], $content);
}

sub build_paste {
	my ($pref, $std) = @_;

	my $garbage = 0;

	D "Running: cwarn.sh -vvv -c '$std' '$pref->{'URL'}' 'paste_garbage.c'";
	my @out = `cwarn.sh -vvv -c '$std' '$pref->{'URL'}' 'paste_garbage.c'`;
	if (${^CHILD_ERROR_NATIVE} != 0) {
		#irc_print("PRIVMSG #hutzelbrutzel :\x01ACTION twitches involuntarily.\x01");
		my $reason = '(no reason)';
		if ($out[0]) {
			chop $out[0];
			$reason = $out[0];
		}
		W "cwarn.sh failed ($reason)";
		L "Could build that ($reason)";
		return;
	}

	if (@out and $out[0] =~ /^BAD/) {
		my $reason = '(no reason)';
		chop $out[0];
		$reason = $out[0] =~ s/^BAD //r;
		W "cwarn.sh failed ($reason)";
		L "cwarn complained ($reason)";
		return;
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
		if ($ln =~ /^BEGIN/) {
			$count++;
			my @arr = split ' ', $ln;

			$aref = $res{$arr[1]};
			$aind = @{ $aref };
			shift @arr;
			$pall .= join(' ', @arr);
			shift @arr;
			${ $aref }[$aind] = join ' ', @arr;
		} elsif ($ln =~ /^END/) {
			$pall .= "\n\n";
		} else {
			${ $aref }[$aind] .= ($ln =~ s/^DATA /\n/r);
			$pall .= ($ln =~ s/^DATA /\n/r);
		}
	}

	D "Result counts: OKAY: ".(scalar @{$res{'OKAY'}}).", NOCOMPILE: ".(scalar @{$res{'NOCOMPILE'}}).", WARNEDC: ".(scalar @{$res{'WARNEDC'}}).", NOLINK: ".(scalar @{$res{'NOLINK'}}).", WARNEDL: ".(scalar @{$res{'WARNEDL'}})."";
	L "OKAY: ".(scalar @{$res{'OKAY'}}).", NOCOMPILE: ".(scalar @{$res{'NOCOMPILE'}}).", WARNEDC: ".(scalar @{$res{'WARNEDC'}}).", NOLINK: ".(scalar @{$res{'NOLINK'}}).", WARNEDL: ".(scalar @{$res{'WARNEDL'}})."";

	my $origprog = "\n\n\n------------------------------------------------------------------------\n";
	$origprog .= "Original program was:\n\n";

	open my $handle, '<', 'paste_garbage.c';
	my @lines = <$handle>;

	my $lc = 0;
	foreach my $ln (@lines) {
		$lc++;
		$origprog .= $lc . "\t" . $ln;
	}

	close $handle;
	$origprog .= "\n------------------------------------------------------------------------\n";

	$pall .= $origprog;
	open $handle, '>', 'paste_result';
	print $handle "$pall";
	close $handle;


	#@out = `curl -s -F 'sprunge=<-' http://sprunge.us <paste_result`;
	D "Running: pstd paste_result";
	@out = `pstd paste_result`;
	$pall = $out[0];
	chop $pall;

	return $pall;
}

sub store_paste {
	my ($href, $content) = @_;

	my $fn = "pdb/$href->{'TIME'}.$href->{'NICK'}";
	D "Storing paste as 'pdb/$fn'";
	my $hnd;
	if (!open $hnd, '>', "$fn") {
		W "open '$fn': $!";
		return '';
	}

	foreach my $k (keys %{$href}) {
		# this works because we can't have newlines anywhere
		print $hnd "$k $href->{$k}\n";
	}
	print $hnd "END\n";
	print $hnd $content if $content;

	close $hnd;

	return $fn;
}

sub retrieve_paste {
	my ($n, $nick, $chan, $msg) = @_;

	$n = -1 unless $n;

	my $rev = '';
	if ($n < 0) {
		$n = -$n;
		$rev = '-r';
	}

	my $cmdline = 'cd pdb ; ls';
	$cmdline .= " | grep -i -- '\.\Q$nick\E\$'" if $nick;

	$cmdline .= " | xargs grep -il '^CHAN \Q$chan\E\$" if $chan;
	$cmdline .= " | xargs grep -il '^MSG .*".($msg =~ s/[\`\'\$]/./rg)."'" if $msg; # XXX probably still dangerous

	$cmdline .= " | sort -n $rev";

	$cmdline .= " | sed -n -e ${n}p -e ${n}q";

	D "Running: $cmdline";
	my @out = `$cmdline`;
	if (${^CHILD_ERROR_NATIVE} != 0 or !@out) {
		W "That failed!";
		return {};
	}

	chop $out[0];
	my $fn = $out[0];
	W "That's file '$fn'";

	my $hnd;
	if (!open $hnd, '<', "pdb/$fn") {
		W "Failed to open '$fn' for reading: $!";
		return {};
	}

	my $h = {};
	while (my $line = <$hnd>) {
		chop $line;
		last if $line =~ /^END$/; #everything below is actual paste data for grepping
		my $key = $line =~ s/ .*$//r;
		my $val = $line =~ s/^[^ ]* //r;
		$h->{$key} = $val;
	}

	return $h;
}

sub mocks {
	my @arr = ('mocks', 'molests', 'harasses', 'picks on', 'vomits at', 'glares at', 'cringes at', 'hates', 'curses', 'stabs');
	return $arr[rand @arr];
}

sub substandard {
	my @arr = ('substandard', 'horrible', 'mind-bogglingly dumb', 'ill-designed', 'shit-grade');
	return $arr[rand @arr];
}

sub poor {
	my @arr = ('poor', 'dumb', 'idiotic', 'questionable', 'bizarre');
	return $arr[rand @arr];
}

sub crapsite {
	my $poor = poor;
	my $subst = substandard;
	my $art = $subst =~ /^[aeiou]/ ? 'an' : 'a';
	my @arr = (
		"using $art $subst paste site",
		"using $art $subst paste site", #this is dumb
		"using $art $subst paste site",
		"their $poor choice of paste sites",
		"their $poor choice of paste sites",
		"their $poor choice of paste sites",
		'their bizarre idea of what constitutes a good paste site',
		'not being able to find a half-decent paste site',
		'not even getting their choice of paste sites right'
	);
	return $arr[rand @arr];
}

sub mock {
	my ($chan, $nick) = @_;
	if (exists $mocked{$nick}) {
		my $ago = time - $mocked{$nick};
		return if ($ago < $mockint);
	}

	$mocked{$nick} = time;

	irc_print("PRIVMSG $chan :\x01ACTION ".mocks." $nick for ".crapsite.".\x01");
}


# -------- IRC --------


# resolve, connect and log on to IRC server
sub irc_connect {
	my ($host, $pass, $nick, $uname, $fname) = @_;
	my ($srv, $port) = split ':', $host; #no ipv6 ATM
	D "resolving '$host' ('$srv' port '$port')...";
	my ($err, @res) = getaddrinfo($srv, $port, {socktype => SOCK_STREAM});
	if ($err) {
		W "getaddrinfo() failed: $!";
		return '';
	}

	D "resolved!";

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

	unless ($sck) {
		W "could not get a socket connected";
		return '';
	}

	irc_print("PASS $pass") if $pass;
	irc_print("NICK $nick");
	irc_print("USER $uname 8 * :$fname");

	my $sel = IO::Select->new();
	$sel->add($sck);

	while (my $line = irc_read($sel, $read_timeout)) {
		D "READ '$line'" unless $line eq "T";
		my @tok = irc_tknz($line);
		if ($tok[1] eq "001") {
			last;
		} elsif ($tok[1] eq "PING") {
			irc_print("PONG :$tok[2]");
		} elsif ($tok[1] eq "432" # various messgaes indicating
		    or $tok[1] eq "433"   # that we need to change nick
		    or $tok[1] eq "436"
		    or $tok[1] eq "437") {
			$nick = "${nick}_";
			irc_print("NICK $nick");
		}
	}

	return $sck;
}

sub irc_read {
	my ($sel, $timeout) = @_;
	if (!!$sel->can_read($timeout)) {
		my $line = <$sck>;
		return $line;
	}

	return "T"; #meh.
}

sub irc_print {
	my ($msg) = @_;
	D "WRITE '$msg'" unless $msg =~ /^P[IO]NG/;
	print $sck $msg."\r\n";
	#D time."\tWRITE\t'$msg'" unless $msg =~ /^P[IO]NG/;
}

# parse IRC protocol message into array of parameters; return that array.
# first element will be the prefix, if present; command and arguments (if
# present) follow in subsequent elements (i.e. [1] will always be the `command')
sub irc_tknz {
	my $line = $_[0] =~ s/\x0D?\x0A$//r;
	my @spl = split(" ", $line);

	my @tok;
	$tok[0] = substr(shift(@spl), 1) if ($line =~ /^:/);

	my $i = 1;
	while (my $t = shift(@spl)) {
		if ($t =~ /^:/) {
			$tok[$i] = substr($t, 1)." ".join(" ", @spl);
			$tok[$i++] =~ s/  *$//;
			last;
		}
		$tok[$i++] = $t;
	}


	return @tok;
}


# -------- Helpers --------


sub time_interval {
	my ($t) = @_;
	my $tdiff = time - $t;

	my $unit;
	if ($tdiff < 60) {
		$unit = 'second';
	} elsif ($tdiff < 60*60) {
		$unit = 'minute';
		$tdiff /= 60;
	} elsif ($tdiff < 24*60*60) {
		$unit = 'hour';
		$tdiff /= 60*60;
	} elsif ($tdiff < 365*24*60*60) {
		$unit = 'day';
		$tdiff /= 24*60*60;
	} else {
		$tdiff /= 365*24*60*60;
		$unit = 'year';
	}

	$tdiff = int($tdiff);

	$unit .= 's' if ($tdiff != 1);

	return "$tdiff $unit";
}

sub whose {
	my ($pref) = @_;
	my $nickposs = "$pref->{'NICK'}'";
	$nickposs .= 's' unless $pref->{'NICK'} =~ /s$/;

	return $nickposs;
}

sub attrs {
	my ($pref) = @_;
	my $subst = exists $pref->{'SUBSTANDARD'} ? ' substandard' : '';
	my $garb = exists $pref->{'GARBAGE'} ? ' garbage' : '';

	return $subst.$garb;
}

sub see {
	my @arr = ('See', 'Consider', 'Check', 'Check out', 'Here you go:');
	return $arr[rand @arr];
}

sub huh {
	my ($nick) = @_;
	my @arr = ('Huh?', 'Eh?', 'What?', 'Hm?', "Come again, $nick?", "I didn't quite catch that, $nick.", 'Stop confusing me.',
	           "Why would you even say that, $nick?");
	return $arr[rand @arr];
}

sub insult {
	my ($na) = @_;

	my $adj = '';
	my @array;
	my %burned = ();
	if ($na > 0) {
		open FILE, "<$iadjfile" or die "Could not open $iadjfile: $!\n";
		@array = <FILE>;
		close FILE;


		my $want = $na;
		while ($want > 0) {
			my $cand = rand @array;
			next if $burned{$cand};
			$burned{$cand} = 1;
			$adj .= ', '.$array[$cand] =~ s/\x0D?\x0A$//r;
			$want--;
		}

		$adj =~ s/^, //;
	}

	open FILE, "<$inounfile" or die "Could not open $inounfile: $!\n";
	@array = <FILE>;
	close FILE;
	my $noun = $array[rand @array] =~ s/\x0D?\x0A$//r;

	return "$adj $noun" =~ s/^ //r;
}


while (1) {
	D "Session start!";
	session;
	D "Session end!";
	sleep 1; # rate limit in case of repeated failure
}
