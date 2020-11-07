use v6.d;
unit package Async::Workers;

class CX does X::Control is export {}
class CX::AW is CX { }

class CX::AW::StopWorker is CX::AW {
    has $.rc;
}
