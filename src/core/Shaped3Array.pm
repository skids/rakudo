    my role Shaped3Array[::TValue] does ShapedArray[TValue] {
        multi method AT-POS(::?CLASS:D: int \one, int \two, int \three) is raw {
            nqp::ifnull(
              nqp::atpos3d(
                nqp::getattr(self,List,'$!reified'),
                one, two, three),
              self!AT-POS-CONTAINER(one, two, three)
            )
        }
        multi method AT-POS(::?CLASS:D: Int:D \one, Int:D \two, Int:D \three) is raw {
            nqp::ifnull(
              nqp::atpos3d(
                nqp::getattr(self,List,'$!reified'),
                one, two, three),
              self!AT-POS-CONTAINER(one, two, three)
            )
        }
        method !AT-POS-CONTAINER(int \one, int \two, int \three) is raw {
            nqp::p6bindattrinvres(
              (my $scalar := nqp::p6scalarfromdesc(
                nqp::getattr(self,Array,'$!descriptor'))),
              Scalar,
              '$!whence',
              -> { nqp::bindpos3d(
                     nqp::getattr(self,List,'$!reified'),
                     one, two, three, $scalar) }
            )
        }
    }

# vim: ft=perl6 expandtab sw=4
