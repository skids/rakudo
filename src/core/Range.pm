my class X::Range::InvalidArg { ... }

my class Range is Cool does Iterable does Positional {
    has $.min;
    has $.max;
    has $.excludes-min;
    has $.excludes-max;
    has $.infinite;
    method is-lazy { self.infinite }

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
    multi method new($min is copy, $max is copy, :$excludes-min, :$excludes-max) {
        $min = +$min
          if nqp::istype($min,List) || nqp::istype($min,Match);
        $max = +$max
          if nqp::istype($max,List) || nqp::istype($max,Match);
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

    multi method EXISTS-POS(Range:D: int \pos) {
        pos < self.elems;
    }

    multi method EXISTS-POS(Range:D: Int \pos) {
        pos < self.elems;
    }

    method elems {
        return Inf if $!min === -Inf || $!max === Inf;
        if nqp::istype($!min, Int) && nqp::istype($!max, Int) {
            my Int:D $least =
              $!excludes-min ?? $!min + 1 !! $!min;
            return 1 + ($!excludes-max ?? $!max.Int - 1 !! $!max.Int) - $least;
        }
        nextsame;
    }

    # XXX GLR steal this logic into the (to be written) iterator for ranges.
    #method reify($n) {
    #    my $count;
    #    my $cmpstop = $!excludes-max ?? 0 !! 1;
    #    my $realmax = nqp::istype($!min, Numeric) && !nqp::istype($!max, Callable) && !nqp::istype($!max, Whatever)
    #                  ?? $!max.Numeric
    #                  !! $!max;
    #
    #    if nqp::istype($value, Num) {
    #        # optimized for num ranges
    #        $value = $value.Num;
    #        my $max = $!max.Num;
    #        my $box_int = nqp::p6bool(nqp::istype($!min, Int));
    #        my num $nvalue = $value;
    #        my num $ncount = $count;
    #        my num $nmax = $max;
    #        my int $icmpstop = $cmpstop;
    #        my int $ibox_int = $box_int;
    #        nqp::while(
    #            (nqp::isgt_n($ncount, 0e0) && nqp::islt_i(nqp::cmp_n($nvalue, $nmax), $icmpstop)),
    #            nqp::stmts(
    #                nqp::push($rpa, $ibox_int
    #                    ?? nqp::p6box_i($nvalue)
    #                    !! nqp::p6box_n($nvalue)),
    #                ($nvalue = nqp::add_n($nvalue, 1e0)),
    #                ($ncount = nqp::sub_n($ncount, 1e0))
    #            ));
    #        $value = nqp::p6box_i($nvalue);
    #    }
    #    else {
    #      SEQ(nqp::push($rpa, $value++); $count--)
    #          while $count > 0 && ($value cmp $realmax) < $cmpstop;
    #    }
    #    if ($value cmp $!max) < $cmpstop {
    #        nqp::push($rpa,
    #            ($value.succ cmp $!max < $cmpstop)
    #               ?? nqp::create(self).BUILD($value, $!max, 0, $!excludes-max)
    #               !! $value);
    #    }
    #}
    method iterator() {
        # Obtain starting value.
        my $value = $!excludes-min ?? $!min.succ !! $!min;

        # Iterating a Str range delegates to iterating a sequence.
        if nqp::istype($value, Str) {
            $value after $!max
                ?? ().iterator
                !! SEQUENCE($value, $!max, :exclude_end($!excludes-max)).iterator
        }

        # If the value and the maximum are both integers and fit in a native
        # int, we have a really cheap approach.
        elsif nqp::istype($value, Int) && nqp::istype($!max, Int) &&
              !nqp::isbig_I(nqp::decont($value)) && !nqp::isbig_I(nqp::decont($!max)) {
            class :: does Iterator {
                has int $!i;
                has int $!n;

                method new(int $i, int $n) {
                    my \iter = self.CREATE;
                    nqp::bindattr_i(iter, self, '$!i', $i);
                    nqp::bindattr_i(iter, self, '$!n', $n);
                    iter
                }

                method pull-one() {
                    my int $i = $!i;
                    $!i = $i + 1;
                    $i <= $!n ?? $i !! IterationEnd
                }

                # XXX GLR implement push-exactly and push-at-least for the
                # performance win!
            }.new($value, $!excludes-max ?? $!max - 1 !! $!max)
        }

        # Also something quick and easy for 1..* style things.
        elsif nqp::istype($value, Numeric) && $!max === Inf {
            class :: does Iterator {
                has $!i;

                method new($i is copy) {
                    my \iter = self.CREATE;
                    nqp::bindattr(iter, self, '$!i', $i);
                    iter
                }

                method pull-one() {
                    $!i++
                }

                method is-lazy() { True }
            }.new($value)
        }

        # General case according to spec
        else {
            class :: does Iterator {
                has $!i;
                has $!e;
                has $!exclude;

                method new($i is copy, $exclude is copy, $e is copy) {
                    my \iter = self.CREATE;
                    nqp::bindattr(iter, self, '$!i', $i);
                    nqp::bindattr(iter, self, '$!e', $e);
                    nqp::bindattr(iter, self, '$!exclude', $exclude);
                    iter
                }

                method pull-one() {
                    if $!exclude ?? $!i before $!e !! not $!i after $!e {
                        my Mu $i = $!i;
                        $!i = $i.succ;
                        $i
                    }
                    else {
                        IterationEnd
                    }
                }
            }.new($value, $!excludes-max, $!max)
        }
    }
    multi method list(Range:D:) { List.from-iterator(self.iterator) }
    method flat(Range:D:) { Seq.new(self.iterator) }

    method bounds()   { (nqp::decont($!min), nqp::decont($!max)) }

    method fmt(|c) {
        self.list.fmt(|c)
    }

    multi method Str(Range:D:) { self.list.Str }

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

    multi method AT-POS(Range:D: int \pos) {
        self.list.AT-POS(pos);
    }
    multi method AT-POS(Range:D: Int:D \pos) {
        self.list.AT-POS(nqp::unbox_i(pos));
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

    multi method Numeric(Range:D:) {
        nextsame unless nqp::istype($.max,Numeric) && nqp::istype($.min,Numeric);

        my $diff := $.max - $.min - $.excludes-min;

        # empty range
        return 0 if $diff < 0;

        my $floor := $diff.floor;
        $floor + 1 - ($floor == $diff ?? $.excludes-max !! 0);
    }
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
