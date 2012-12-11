package WrongMX;
use strict;
use Mail::SpamAssassin;
use Mail::SpamAssassin::Plugin;
use Net::DNS;
our @ISA = qw(Mail::SpamAssassin::Plugin);

sub new {
  my ($class, $mailsa) = @_;
  $class = ref($class) || $class;
  my $self = $class->SUPER::new($mailsa);
  bless ($self, $class);
  $self->register_eval_rule("wrongmx");
  return $self;
}

sub wrongmx {
  my ($self, $permsgstatus) = @_;
  my $MAXTIMEDIFF = 30;

  return 0 if $self->{main}->{local_tests_only}; # in case plugins ever get called

  # if a user set dns_available to no we shouldn't be doing MX lookups
  return 0 unless $permsgstatus->is_dns_available();

  # avoid FPs (and wasted processing) by not checking when all_trusted
  return 0 if $permsgstatus->check_all_trusted;

  # if there is only one received header we can bail
  my $times_ref = ($permsgstatus->{received_header_times});
  return 0 if (!defined($times_ref) || scalar(@$times_ref) < 2); # if it only hit one server we're done

  # next we need the recipient domain's MX records... who's the recipient
  my $recipient_domain;
  if ($self->{main}->{username} =~ /\@(\S+\.\S+)/) {
    $recipient_domain = $1;
  } else {
    foreach my $to ($permsgstatus->all_to_addrs) {
      next unless defined $to;
      $to =~ tr/././s; # bug 3366?
      if ($to =~ /\@(\S+\.\S+)/) {
        $recipient_domain = $1;
        last;
      }
    }
  }
  return 0 unless defined $recipient_domain;  # no domain means no MX records

  # Now we need to get the recipient domain's MX records.
  # We'll resolve the hosts so we can look for IP overlaps.
  my $res = Net::DNS::Resolver->new;
  my @rmx = mx($res, $recipient_domain);
  my %mx_prefs;
  if (@rmx) {
    foreach my $rr (@rmx) {
      unless (exists $mx_prefs{$rr->exchange} && $mx_prefs{$rr->exchange} < $rr->preference) {
        $mx_prefs{$rr->exchange} = $rr->preference;
      }
      my @ips = $permsgstatus->lookup_a($rr->exchange);
      next unless @ips;
      foreach my $ip (@ips) {
        unless (exists $mx_prefs{$ip} && $mx_prefs{$ip} < $rr->preference) {
          $mx_prefs{$ip} = $rr->preference;
        }
      }
    }
  } else {
    return 0; # no recipient domain MX records found, no way to check MX flow
  }

  # get relay hosts
  my @relays;
  foreach my $rcvd (@{$permsgstatus->{relays_trusted}}, @{$permsgstatus->{relays_untrusted}}) {
    push @relays, $rcvd->{by};
  }
  return 0 if (!scalar(@relays)); # this probably won't happen, but whatever

  # Bail if we don't have the same number of relays and times, or if we have
  # fewer preferences than times (or relays).
  return 0 if (scalar(@relays) != scalar(@$times_ref) || scalar(@$times_ref) > scalar(keys(%mx_prefs)));

  # Check to see if a higher preference relay passes mail to a lower
  # preference relay within $MAXTIMEDIFF seconds.  If we do decide that a message
  # has done this, wait till AFTER we lookup the sender domain's MX records
  # to return 1 since there may be MX overlaps that we'll bail on... see below.
  # We could do the sender domain MX lookups first, but we might as well save
  # the overhead if we're going to end up bailing anyway ($hits == 0).

  # We'll go through backwards so that we can detect weird local configs
  # that pass mail from the primary MX to the secondary MX for spam/virus
  # scanning, or even final delivery.  See BACKWARDS comment below.

  # We'll resolve the 'by' hosts found to see if they match any of our
  # resolved MX hosts' IPs.

  my $hits = 0;
  my $last_pref;
  my $last_time;
  foreach (my $i = $#relays; $i >= 0; $i--) {
    my $MX = 0;
    if (exists($mx_prefs{$relays[$i]})) {
      $MX = $relays[$i];
    } else {
      my @ips = $permsgstatus->lookup_a($relays[$i]);
      next unless @ips;

      foreach my $ip (@ips) {
        if ( exists $mx_prefs{$ip} ) {
         $MX = $ip;
          last;
        }
      }
    }
    if ($MX) {
      if (defined ($last_pref) && defined ($last_time)) {
        # BACKWARDS -- uncomment the next line if you need to pass mail from a
        # higher pref MX to a lower MX (for virus scanning/etc) AND back,
        # before SA sees it... this opens you up to FNs with forged headers
     #   last if ($mx_prefs{$MX} > $last_pref);

        $hits++ if ($mx_prefs{$MX} < $last_pref
          && ($last_time - $MAXTIMEDIFF <= @$times_ref[$i] && @$times_ref[$i] <= $last_time + $MAXTIMEDIFF) ); # within max time diff
      }
      $last_pref = $mx_prefs{$MX};
      $last_time = @$times_ref[$i];
    }
    last if $hits;
  }

  # Determine the sender's domain.
  # Don't bail if we can't determine the sender since it's probably spam.
  my $sender_domain;
  foreach my $from ($permsgstatus->get('EnvelopeFrom:addr')) {
    next unless defined $from;
    $from =~ tr/././s; # bug 3366?
    if ($from =~ /\@(\S+\.\S+)/) {
      $sender_domain = $1;
      last;
    }
  }
  if (defined $sender_domain) {
 
    # Until SPF is incorporated (to better define possibly shared MX servers) we
    # might as well bail here, and save the MX lookup, if the sender domain is
    # the same as the recipient domain, since the MX records will, obviously,
    # overlap.  See below.
    return 0 if (lc($sender_domain) eq lc($recipient_domain));
 
    # Bail if the recepient and sender domains share the same MX servers.
    # If the sender's primary MX is the recipient's secondary MX we don't want
    # to penalize them.  (Comparing SPF records might also be a good idea.)
    # This will FN if spam comes with a From: as your domain.  SPF should
    # really be implemented here!
    # Ignoring the sender's MX records if an SPF lookup results in failure
    # would help to avoid FNs and should do the job since anyone with an SPF
    # record that shares your MX servers probably won't be spamming you.

    # Again, MX hosts are resolved to look for IP overlaps.
    if ($sender_domain) {
      my @smx = mx($res, $sender_domain);
      if (@smx) {
        foreach my $srr (@smx) {
          foreach my $rrr (@rmx) {
            return 0 if ($rrr->exchange eq $srr->exchange);
          }
          my @sips = $permsgstatus->lookup_a($srr->exchange);
          foreach my $sip (@sips) {
            foreach my $rip (keys %mx_prefs) {
              return 0 if ($rip eq $sip);
            }
          }
        }
      }
    }
  }

  return 1 if $hits;
  return 0;
}

1;
