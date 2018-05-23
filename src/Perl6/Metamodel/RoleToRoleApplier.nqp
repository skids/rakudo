my class RoleToRoleApplier {
    method apply($target, @roles) {
        # Ensure we actually have something to appply.
        unless +@roles {
            return [];
        }

        # Aggregate all of the methods sharing names, eliminating
        # any duplicates (a method can't collide with itself).
        my %meth_info;
        my %meth_providers;
        my %priv_meth_info;
        my %priv_meth_providers;
        for @roles {
            my $role := $_;
            sub build_meth_info(%methods, %meth_info_to_use, %meth_providers_to_use) {
                for %methods {
                    my $name := $_.key;
                    my $meth := $_.value;
                    my @meth_list;
                    my @meth_providers;
                    if nqp::existskey(%meth_info_to_use, $name) {
                        @meth_list := %meth_info_to_use{$name};
                        @meth_providers := %meth_providers_to_use{$name};
                    }
                    else {
                        %meth_info_to_use{$name} := @meth_list;
                        %meth_providers_to_use{$name} := @meth_providers;
                    }
                    my $found := 0;
                    for @meth_list {
                        if $meth =:= $_ {
                            $found := 1;
                        }
                        elsif nqp::can($meth, 'id') && nqp::can($_, 'id') {
                            $found := $meth.id == $_.id;
                        }
                    }
                    unless $found {
                        @meth_list.push($meth);
                        @meth_providers.push($role);
                    }
                }
            }
            build_meth_info($_.HOW.method_table($_), %meth_info, %meth_providers);
            build_meth_info($_.HOW.submethod_table($_), %meth_info, %meth_providers)
                if nqp::can($_.HOW, 'submethod_table');
            build_meth_info($_.HOW.private_method_table($_), %priv_meth_info, %priv_meth_providers)
                if nqp::can($_.HOW, 'private_method_table');
        }

        # Also need methods of target.
        my %target_meth_info := $target.HOW.method_table($target);

        # Process method list.
        for %meth_info {
            my $name := $_.key;
            my @add_meths := %meth_info{$name};
            my @providers := %meth_providers{$name};

            # Do we already have a method of this name? If so, ignore all of the
            # methods we have from elsewhere, but complain if we ignore an
            # insistent one
            if nqp::existskey(%target_meth_info, $name) {
                my $insists := 0;
                my $first_insist;
                my $idx := 0;
                for @add_meths {
                    my $insist := 0;
                    my $provider := NQPMu;
                    try { $provider := $_.package }
                    if $provider =:= NQPMu {
                        # We hit a circular sawtooth.  Fake it.
                        $provider := @providers[$idx];
                    }
                    $insist := $_.insistent;
                    unless $insist {
                        if nqp::iseq_s($provider.HOW.name($provider),'Perl6::Metamodel::CurriedRoleHOW') {
                            $insist := $provider.insistent;
                        }
                        else {
                            $insist := $provider.HOW.insistent($provider);
                        }
                    }
                    if $insist {
                        unless $insists {
                            if nqp::iseq_s($provider.HOW.name($provider),'Perl6::Metamodel::CurriedRoleHOW') {
                                $first_insist := $provider.name($provider);
                            }
                            else {
                                $first_insist := $provider.HOW.name($provider)
                            }
                        }
                        $insists++
                    };
                    $idx++;
                }
                if $insists > 0 {
                    my $mess := 'Warning: Overrode insistent method "' ~ $name
                        ~ '" from role "' ~ $first_insist ~ '"';
                    note($mess);
                }
            }
            else {
                # No methods in the target role. If only one, it's easy...
                if +@add_meths == 1 {
                    $target.HOW.add_method($target, $name, @add_meths[0]);
                }
                else {
                    # Find if any of the methods are actually requirements, not
                    # implementations.  Also eliminate duplicates from diamond
                    # compositions.

                    my @impl_meths;
                    my $diamond := False; # importantly !=:= NQPMu
                    for @add_meths {
                        my $yada := 0;
                        my $pack;
                        try { $yada := $_.yada; }
                        try { $pack := $_.package }
                        unless $yada || ($diamond =:= $pack && nqp::isne_s($pack.HOW.name($pack), 'GLOBAL')) {
                            @impl_meths.push($_);
                        }
                        $diamond := $pack;
                    }

                    # If there's still more than one possible - add to collisions list.
                    # If we got down to just one, add it. If they were all requirements,
                    # just choose one.
                    if +@impl_meths == 1 {
                        $target.HOW.add_method($target, $name, @impl_meths[0]);
                    }
                    elsif +@impl_meths == 0 {
                        $target.HOW.add_method($target, $name, @add_meths[0]);
                    }
                    else {
                        $target.HOW.add_collision($target, $name, %meth_providers{$name}, @impl_meths);
                    }
                }
            }
        }

        # Process private method list.
        if nqp::can($target.HOW, 'private_method_table') {
            my %target_priv_meth_info := $target.HOW.private_method_table($target);
            for %priv_meth_info {
                my $name := $_.key;
                my @add_meths := %priv_meth_info{$name};
                my @providers := %meth_providers{$name};

                # Do we already have a method of this name? If so, ignore all of the
                # methods we have from elsewhere, but complain if we ignore one
                # that is insistent.
                if nqp::existskey(%target_priv_meth_info, $name) {
                    my $insists := 0;
                    my $first_insist;
                    my $idx := 0;
                    for @add_meths {
                        my $insist := 0;
                        my $provider := NQPMu;
                        try { $provider := $_.package; }
                        if $provider =:= NQPMu {
                            # We hit a circular sawtooth.  Fake it.
                            $provider := @providers[$idx];
                        }
                        $insist := $_.insistent;
                        unless $insist {
                            if nqp::iseq_s($provider.HOW.name($provider),'Perl6::Metamodel::CurriedRoleHOW') {
                                $insist := $provider.insistent;
                            }
                            else {
                                $insist := $provider.HOW.insistent($provider);
                            }
                        }
                        if $insist {
                            unless $insists {
                                if nqp::iseq_s($provider.HOW.name($provider),'Perl6::Metamodel::CurriedRoleHOW') {
                                    $first_insist := $provider.name($provider);
                                }
                                else {
                                    $first_insist := $provider.HOW.name($provider)
                                }
                            }
                            $insists++
                        };
                        $idx++;
                    }
                    if $insists > 0 {
                        my $mess := 'Warning: Overrode insistent private method "!' ~ $name
                            ~ '" from role "' ~ $first_insist ~ '"';
                        note($mess);
                    }
                }
                else {
                    if +@add_meths == 1 {
                        $target.HOW.add_private_method($target, $name, @add_meths[0]);
                    }
                    else {
                        # Find if any of the methods are actually requirements, not
                        # implementations.  Also eliminate duplicates from diamond
                        # compositions.
                        my @impl_meths;
                        my $diamond := False; # importantly !=:= NQPMu
                        for @add_meths {
                            my $yada := 0;
                            my $pack;
                            try { $yada := $_.yada; }
                            try { $pack := $_.package }
                            unless $yada || $diamond =:= $pack {
                                @impl_meths.push($_);
                            }
                            $diamond := $pack;
                        }

                        # If there's still more than one possible - add to collisions list.
                        # If we got down to just one, add it. If they were all requirements,
                        # just choose one.
                        if +@impl_meths == 1 {
                            $target.HOW.add_private_method($target, $name, @impl_meths[0]);
                        }
                        elsif +@impl_meths == 0 {
                            # any of the method stubs will do
                            $target.HOW.add_private_method($target, $name, @add_meths[0]);
                        }
                        else {
                            $target.HOW.add_collision($target, $name, %priv_meth_providers{$name}, @impl_meths, :private(1));
                        }
                    }
                }
            }
        }

        # Compose multi-methods; need to pay attention to the signatures.
        my %multis_by_name;
        my %multis_required_by_name;
        for @roles -> $role {
            my $how := $role.HOW;
            if nqp::can($how, 'multi_methods_to_incorporate') {
                for $how.multi_methods_to_incorporate($role) {
                    my $name := $_.name;
                    my $to_add := $_.code;
                    my $yada := 0;
                    try { $yada := $to_add.yada; }
                    if $yada {
                        %multis_required_by_name{$name} := []
                            unless %multis_required_by_name{$name};
                        nqp::push(%multis_required_by_name{$name}, $to_add);
                    }
                    else {
                        if %multis_by_name{$name} -> @existing {
                            # A multi-method can't conflict with itself.
                            my int $already := 0;
                            for @existing {
                                if $_[1] =:= $to_add {
                                    $already := 1;
                                    last;
                                }
                            }
                            nqp::push(@existing, [$role, $to_add]) unless $already;
                        }
                        else {
                            %multis_by_name{$name} := [[$role, $to_add],];
                        }
                    }
                }
            }
        }

        if nqp::can($target.HOW, 'multi_methods_to_incorporate') {
            my %multi_methods_to_incorporate := $target.HOW.multi_methods_to_incorporate($target);
            for %multi_methods_to_incorporate {
                my $name := $_.name;
                my $code := $_.code;

                # Do we already have a method of this name/sig? If so, ignore
                # all of the methods we have from elsewhere, but complain if
                # we ignore an insistent one.
                if nqp::existskey(%multis_by_name, $name) {
                    my @add_meths := %multis_by_name{$name};
                    my $insists := 0;
                    my $insistent_provider;
                    my $insistent_code;
                    my @pruned_meths := [];
                    for @add_meths {
                        my $to_add := $_[1];

                        my $provider := NQPMu;
                        try { $provider := $to_add.package }
                        if $provider =:= NQPMu {
                            # We hit a circular sawtooth.  Fake it.
                            $provider := $_[0];
                        }
                        if Perl6::Metamodel::Configuration.compare_multi_sigs($code, $to_add) {
                            my $insist := $to_add.insistent;
                            unless $insist {
                                if nqp::iseq_s($provider.HOW.name($provider),'Perl6::Metamodel::CurriedRoleHOW') {
                                    $insist := $provider.insistent;
                                }
                                else {
                                    $insist := $provider.HOW.insistent($provider);
                                }
                            }
                            if $insist {
                                unless $insists {
                                    $insistent_code := $to_add;
                                    if nqp::iseq_s($provider.HOW.name($provider),'Perl6::Metamodel::CurriedRoleHOW') {
                                        $insistent_provider := $provider.name($provider);
                                    }
                                    else {
                                        $insistent_provider := $provider.HOW.name($provider);
                                    }
                                }
                                $insists++;
                            };
                        }
                        else {
                            @pruned_meths.push($_);
                        }
                    }
                    %multis_by_name{$name} := @pruned_meths;
                    if $insists > 0 {
                        my $sigstr := "";
                        my $sig := $insistent_code.signature;
                        if nqp::isconcrete($sig) && nqp::can($sig, 'gist') {
                            $sigstr := $sig.gist;
                        }
                        my $mess := 'Warning: Overrode insistent multimethod '
                            ~ 'candidate "' ~ $name ~ $sigstr ~ '" from role "'
                            ~ $insistent_provider ~ '"';
                        note($mess);
                    }
                }
            }
        }


        # Look for conflicts, and compose non-conflicting.
        for %multis_by_name {
            my $name := $_.key;
            my @cands := $_.value;
            my @collisions;
            my @collmeths;
            for @cands -> $c1 {
                my @collides;
                for @cands -> $c2 {
                    unless $c1[1] =:= $c2[1] {
                        if Perl6::Metamodel::Configuration.compare_multi_sigs($c1[1], $c2[1]) {
                            my $p1 := False; # importantly !=:= NQPMu
                            my $p2;

                            try { $p1 := $c1[1].package }
                            try { $p2 := $c2[1].package }
                            unless $p1 =:= $p2 {
                                nqp::push(@collides, $c1[0]);
                                nqp::push(@collmeths, $c1[1]);
                                nqp::push(@collides, $c2[0]);
                                nqp::push(@collmeths, $c2[1]);
                            }
                            last;
                        }
                    }
                }
                if @collides {
                    $target.HOW.add_collision($target, $name, @collides, @collmeths, :multi($c1[1]));
                }
                else {
                    $target.HOW.add_multi_method($target, $name, $c1[1]);
                }
            }
        }

        # Pass on any unsatisfied requirements (note that we check for the
        # requirements being met when applying the summation of roles to a
        # class, so we can avoid duplicating that logic here.)
        for %multis_required_by_name {
            my $name := $_.key;
            for $_.value {
                $target.HOW.add_multi_method($target, $name, $_);
            }
        }

        # Now do the other bits.
        for @roles {
            my $how := $_.HOW;

            # Compose in any attributes, unless there's a conflict.
            my @attributes := $how.attributes($_, :local(1));
            for @attributes {
                my $add_attr := $_;
                my $skip := 0;
                my @cur_attrs := $target.HOW.attributes($target, :local(1));
                my $add_pack := False; # importantly !=:= NQPMu
                try { $add_pack := $_.package }

                for @cur_attrs {
                    my $pack;
                    try { $pack := $_.package }
                    if $_ =:= $add_attr {
                        $skip := 1;
                    }
                    else {
                        if $_.name eq $add_attr.name {
                            if ($pack =:= $add_pack) {
                                $skip := 1;
                            }
                            else {
                                nqp::die("Attribute '" ~ $_.name ~ "' conflicts in role composition");
                            }
                        }
                    }
                }
                unless $skip {
                    $target.HOW.add_attribute($target, $add_attr);
                }
            }
 
            # Any parents can also just be copied over.
            if nqp::can($how, 'parents') {
                my @parents := $how.parents($_, :local(1));
                for @parents {
                    $target.HOW.add_parent($target, $_);
                }
            }
        }

        1;
    }
}
