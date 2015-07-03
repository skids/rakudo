class CompUnit {
    has Lock     $!lock;
    has Str      $.from;
    has Str      $.name;
    has Str      $.extension;
    has Str      $.precomp-ext;
    has IO::Path $.path;
    has Str      $!WHICH;
    has Bool     $.has-source;
    has Bool     $.has-precomp;
    has Bool     $.is-loaded;

    my Lock $global = Lock.new;
    my $default-from = 'Perl6';
    my %instances;

    method new(CompUnit:U:
      $path,
      :$name is copy,
      :$extension is copy,
      :$from = $default-from,
      :$has-source is copy,
      :$has-precomp is copy,
    ) {

        # set name / extension if not already given
        if !$name or !$extension.defined {
            my IO::Spec $SPEC := $*SPEC;
            $name      ||= $SPEC.basename($path);
            $extension ||= $SPEC.extension($name);
        }

        # sanity test
        my $precomp-ext = $*VM.precomp-ext;
        $has-source  //= ?$path.IO.f;
        $has-precomp //= ?"$path.$precomp-ext".IO.f;
        return Nil unless $has-source or $has-precomp;

        $global.protect( { %instances{$path} //= self.bless(
          :path(IO::Path.new-from-absolute-path($path)),
          :lock(Lock.new),
          :$name,
          :$extension,
          :$precomp-ext,
          :$from,
          :$has-source,
          :$has-precomp,
          :!is-loaded,
        ) } );
    }

    multi method WHICH(CompUnit:D:) { $!WHICH //= "{self.^name}|$!path.abspath()" }
    multi method Str(CompUnit:D: --> Str)  { $!path.abspath }
    multi method gist(CompUnit:D: --> Str) { "{self.name}:{$!path.abspath}" }

    method key(CompUnit:D: --> Str) {
        $!has-precomp ?? $!precomp-ext !! $!extension;
    }

    # same magic I'm not sure we need
    my Mu $p6ml := nqp::gethllsym('perl6', 'ModuleLoader');
    method p6ml() { $p6ml }
    method ctxsave() { $p6ml.ctxsave() }
    method absolute_path($path) { $p6ml.absolute_path($path) }
    method load_setting($setting_name) { $p6ml.load_setting($setting_name) }
    method resolve_repossession_conflicts(@conflicts) {
        $p6ml.resolve_repossession_conflicts(
          nqp::findmethod(@conflicts, 'FLATTENABLE_LIST')(@conflicts)
        );
    }

    # do the actual work
    method load(CompUnit:D:
      $module_name,
      %opts,
      *@GLOBALish is rw,
      :$line,
      :$file
    ) {
        $!lock.protect( {

            # nothing to do
            return $!is-loaded if $!is-loaded;

            my $candi = self.candidates($module_name, :auth(%opts<auth>), :ver(%opts<ver>))[0];
            my %chosen;
            if $candi {
                %chosen<pm>   :=
                  $candi<provides>{$module_name}<pm><file>;
                %chosen<pm>   := ~%chosen<pm> if %chosen<pm>.DEFINITE;
                %chosen<load> :=
                  $candi<provides>{$module_name}{$!precomp-ext}<file>;
                %chosen<key>  := %chosen<pm> // %chosen<load>;
            }
            $p6ml.load_module(
              $module_name,
              %opts,
              |@GLOBALish,
              :$line,
              :$file,
              :%chosen
            );
        } );
    }

    method precomp-path(CompUnit:D: --> Str) { "$!path.$!precomp-ext" }

    method precomp(CompUnit:D:
      $out  = self.precomp-path,
      :$INC = @*INC,
      :$force,
    ) {

        my $io = $out.IO;
        die "Cannot pre-compile over a newer existing file: $out"
          if $io.e && !$force && $io.modified > $!path.modified;

        my Mu $opts := nqp::atkey(%*COMPILING, '%?OPTIONS');
        my $lle = !nqp::isnull($opts) && !nqp::isnull(nqp::atkey($opts, 'll-exception'))
          ?? ' --ll-exception'
          !! '';
        %*ENV<RAKUDO_PRECOMP_WITH> = CREATE-INCLUDE-SPECS(@$INC);

RAKUDO_MODULE_DEBUG("Precomping with %*ENV<RAKUDO_PRECOMP_WITH>")
  if $?RAKUDO_MODULE_DEBUG;

        my $cmd = "$*EXECUTABLE$lle --target={$*VM.precomp-target} --output=$out $!path";
        my $proc = shell("$cmd 2>&1", :out, :!chomp);
        %*ENV<RAKUDO_PRECOMP_WITH>:delete;

        my $result = '';
        $result ~= $_ for $proc.out.lines;
        $proc.out.close;
        if $proc.status -> $status {  # something wrong
            $result ~= "Return status $status\n";
            fail $result if $result;
        }
        note $result if $result;


        $!has-precomp = True if $out eq self.precomp-path;
        True;
    }
}

# TEMPORARY ACCESS TO COMPUNIT INTERNALS UNTIL WE CAN LOAD DIRECTLY
multi sub postcircumfix:<{ }> (CompUnit:D \c, "provides" ) {
    my % = (
      c.name => {
        pm => {
          file => c.path
        },
        c.key => {
          file => c.has-precomp ?? c.precomp-path !! c.path
        }
      }
    );
}
multi sub postcircumfix:<{ }> (CompUnit:D \c, "key" ) {
    c.key;
}
multi sub postcircumfix:<{ }> (CompUnit:D \c, "ver" ) {
    Version.new('0');
}
