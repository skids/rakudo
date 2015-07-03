my class X::Range::InvalidArg { ... }

my class Range is Iterable is Cool does Positional {
    has $.min;
    has $.max;
    has $.excludes-min;
    has $.excludes-max;
    has $.infinite;

    proto method new(|) { * }
    # The order of "method new" declarations matters here, to ensure
    # appropriate candidate tiebreaking when mixed type arguments
    # are present (e.g., Range,Whatever or Real,Range).
    multi method new(Range $min, $max, :$excludes-min, :$excludes-max) {
        X::Range::InvalidArg.new(:got($min)).throw;
    }
    multi method new($min, Range $max, :$excludes-min, :$excludes-max) {
        X::Range::InvalidArg.new(:got($max)).throw;
    }
    multi method new(Whatever $min, Whatever $max, :$excludes-min, :$excludes-max) {
        nqp::create(self).BUILD(-Inf, Inf, $excludes-min, $excludes-max, True);
    }
    multi method new(Whatever $min, $max, :$excludes-min, :$excludes-max) {
        nqp::create(self).BUILD(-Inf, $max, $excludes-min, $excludes-max, True);
    }
    multi method new($min, Whatever $max, :$excludes-min, :$excludes-max) {
        nqp::create(self).BUILD($min, Inf, $excludes-min, $excludes-max, True);
    }
    multi method new(Real $min, Real() $max, :$excludes-min, :$excludes-max) {
        nqp::create(self).BUILD(
          $min,
          $max,
          $excludes-min,
          $excludes-max,
          $max == Inf || $min == -Inf,
        );
    }
    multi method new($min is copy, $max, :$excludes-min, :$excludes-max) {
        $min = +$min
          if nqp::istype($min,List) || nqp::istype($min,Match) || nqp::istype($min,Parcel);
        nqp::create(self).BUILD($min, $max, $excludes-min, $excludes-max);
    }

    submethod BUILD(
      $!min,
      $!max,
      Bool() $!excludes-min,
      Bool() $!excludes-max,
      Bool   $!infinite = False,
    ) {
        self;
    }

    multi method WHICH (Range:D:) {
        self.^name
          ~ "|$!min"
          ~ ("^" if $!excludes-min)
          ~ '..'
          ~ ("^" if $!excludes-max)
          ~ $!max;
    }

    method flat()     { nqp::p6list(nqp::list(self), List, Bool::True) }
    method iterator() { self }
    method list()     { self.flat }

    method bounds()   { ($!min, $!max) }

    multi method ACCEPTS(Range:D: Mu \topic) {
        (topic cmp $!min) > -(!$!excludes-min)
            and (topic cmp $!max) < +(!$!excludes-max)
    }

    multi method ACCEPTS(Range:D: Range \topic) {
        (topic.min > $!min
         || topic.min == $!min
            && !(!topic.excludes-min && $!excludes-min))
        &&
        (topic.max < $!max
         || topic.max == $!max
            && !(!topic.excludes-max && $!excludes-max))
    }

    method reify($n) {
        my $value = $!excludes-min ?? $!min.succ !! $!min;
        # Iterating a Str range delegates to iterating a sequence.
        if Str.ACCEPTS($value) {
            return $value after $!max
                     ?? ()
                     !! SEQUENCE($value, $!max, :exclude_end($!excludes-max)).iterator.reify($n)
        }
        my $count;
        if nqp::istype($n, Whatever) {
            $count = self.infinite ?? 10 !! Inf;
        }
        else {
            $count = $n.Num max 1024e0;
            fail "request for infinite elements from range"
              if $count == Inf && self.infinite;
        }
        my $cmpstop = $!excludes-max ?? 0 !! 1;
        my $realmax = nqp::istype($!min, Numeric) && !nqp::istype($!max, Callable) && !nqp::istype($!max, Whatever)
                      ?? $!max.Numeric
                      !! $!max;

        # Pre-size the buffer, to avoid reallocations.
        my Mu $rpa := nqp::list();
        nqp::setelems($rpa, $count == Inf ?? 256 !! $count.Int);
        nqp::setelems($rpa, 0);

        if nqp::istype($value, Int) && nqp::istype($!max, Int) && !nqp::isbig_I(nqp::decont $!max)
           || nqp::istype($value, Num) {
            # optimized for int/num ranges
            $value = $value.Num;
            my $max = $!max.Num;
            my $box_int = nqp::p6bool(nqp::istype($!min, Int));
            my num $nvalue = $value;
            my num $ncount = $count;
            my num $nmax = $max;
            my int $icmpstop = $cmpstop;
            my int $ibox_int = $box_int;
            nqp::while(
                (nqp::isgt_n($ncount, 0e0) && nqp::islt_i(nqp::cmp_n($nvalue, $nmax), $icmpstop)),
                nqp::stmts(
                    nqp::push($rpa, $ibox_int
                        ?? nqp::p6box_i($nvalue)
                        !! nqp::p6box_n($nvalue)),
                    ($nvalue = nqp::add_n($nvalue, 1e0)),
                    ($ncount = nqp::sub_n($ncount, 1e0))
                ));
            $value = nqp::p6box_i($nvalue);
        }
        else {
          SEQ(nqp::push($rpa, $value++); $count--)
              while $count > 0 && ($value cmp $realmax) < $cmpstop;
        }
        if ($value cmp $!max) < $cmpstop {
            nqp::push($rpa,
                ($value.succ cmp $!max < $cmpstop)
                   ?? nqp::create(self).BUILD($value, $!max, 0, $!excludes-max)
                   !! $value);
        }
        nqp::p6parcel($rpa, nqp::null());
    }

    multi method AT-POS(Range:D: int \pos) {
        self.flat.AT-POS(pos);
    }
    multi method AT-POS(Range:D: Int:D \pos) {
        self.flat.AT-POS(nqp::unbox_i(pos));
    }

    multi method perl(Range:D:) {
        $.min.perl
          ~ ('^' if $.excludes-min)
          ~ '..'
          ~ ('^' if $.excludes-max)
          ~ $.max.perl
    }

    proto method roll(|) { * }
    multi method roll(Range:D: Whatever) {
        gather loop { take self.roll }
    }
    multi method roll(Range:D:) {
        return self.list.roll
          unless nqp::istype($!min, Int) && nqp::istype($!max, Numeric);

        my Int:D $least =
          $!excludes-min ?? $!min + 1 !! $!min;
        my Int:D $elems =
          1 + ($!excludes-max ?? $!max.Int - 1 !! $!max.Int) - $least;
        $elems ?? ($least + nqp::rand_I(nqp::decont($elems), Int)) !! Any;
    }
    multi method roll(Int(Cool) $num) {
        return self.list.roll($num)
          unless nqp::istype($!min, Int) && nqp::istype($!max, Numeric);

        my Int:D $least =
          $!excludes-min ?? $!min + 1 !! $!min;
        my Int:D $elems =
          1 + ($!excludes-max ?? $!max.Int - 1 !! $!max.Int) - $least;

        my int $todo = nqp::unbox_i($num.Int);
        if $elems {
            gather while $todo {
                take $least + nqp::rand_I(nqp::decont($elems), Int);
                $todo = $todo - 1;
            }
        }
        else {
            Any xx $todo;
        }
    }

    proto method pick(|)        { * }
    multi method pick()          { self.roll };
    multi method pick(Whatever)  { self.list.pick(*) };
    multi method pick(Int(Cool) $n) {
        return self.list.pick($n)
          unless nqp::istype($!min, Int) && nqp::istype($!max, Numeric);

        my Int:D $least =
          $!excludes-min ?? $!min + 1 !! $!min;
        my Int:D $elems =
          1 + ($!excludes-max ?? $!max.Int - 1 !! $!max.Int) - $least;
        my int $todo = nqp::unbox_i($n.Int);

        # faster to make list and then take from there
        return self.list.pick($n) if $elems < 3 * $todo;

        my %seen;
        gather while $todo {
            my Int $x  := $least + nqp::rand_I(nqp::decont($elems), Int);
            unless %seen.EXISTS-KEY($x) {
                %seen{$x} = 1;
                take $x;
                $todo = $todo - 1;
            }
        }
    }

    multi method Numeric (Range:D:) {
        nextsame unless nqp::istype($.max,Numeric) && nqp::istype($.min,Numeric);

        my $diff := $.max - $.min - $.excludes-min;

        # empty range
        return 0 if $diff < 0;

        my $floor := $diff.floor;
        $floor + 1 - ($floor == $diff ?? $.excludes-max !! 0);
    }

    method excludes_min() { DEPRECATED('excludes-min', |<2014.12 2015.09>); $!excludes-min }
    method excludes_max() { DEPRECATED('excludes-max', |<2014.12 2015.09>); $!excludes-max }
}

sub infix:<..>($min, $max) is pure {
    Range.new($min, $max)
}
sub infix:<^..>($min, $max) is pure {
    Range.new($min, $max, :excludes-min)
}
sub infix:<..^>($min, $max) is pure {
    Range.new($min, $max, :excludes-max)
}
sub infix:<^..^>($min, $max) is pure {
    Range.new($min, $max, :excludes-min, :excludes-max)
}
sub prefix:<^>($max) is pure {
    Range.new(0, $max.Numeric, :excludes-max)
}

multi sub infix:<eqv>(Range:D \a, Range:D \b) {
       a.min eqv b.min
    && a.max eqv b.max
    && a.excludes-min eqv b.excludes-min
    && a.excludes-max eqv b.excludes-max
}

# vim: ft=perl6 expandtab sw=4
