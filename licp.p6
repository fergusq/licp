#!/usr/bin/env perl6

my $counter = 0;
sub counter returns Int { $counter++ }

class Output {
    has Str $.header-buffer is rw = "";
    has Str $.command-buffer is rw = "";
    has Str $.expr-buffer is rw = "";

    method header(Str $s) {
        $.header-buffer ~= $s ~ "\n";
    }

    method command(Str $s) {
        $.command-buffer ~= "  $s\n";
    }

    method return(Str $s) {
        $.expr-buffer = $s;
    }

    method merge(Output $other) returns Str {
        $.header-buffer ~= $other.header-buffer;
        $.command-buffer ~= $other.command-buffer;
        return $other.expr-buffer
    }

    method merge-header(Output $other, Str $ret) returns Str {
        $.header-buffer ~= $other.header-buffer;
        "{$other.command-buffer}  $ret {$other.expr-buffer};"
    }

    method to-string {
        "#include <stdio.h>\n#include <stdlib.h>\n#include \"licp.h\"\n\n$.header-buffer\nint main() \{\n$.command-buffer\n  printf(\"%d\\n\", $.expr-buffer.i);\n\}"
    }
}

sub output(&f) returns Output {
    my $output = Output.new();
    &f($output);
    $output
}

class Scope {
    has Int %.variables;

    method add-variable(Str $varname) {
        $.variables{$varname} = ($.variables.values.max max -1) + 1;
    }

    method clone returns Scope {
        Scope.new(variables => $.variables.clone())
    }
}

class Node {
    method to-symbol returns Str { ... }
    method to-str-list returns Array[Str] { ... }
    method to-c(Scope --> Str) { ... }
}

class IntSym is Node {
    has Int $.int;

    method to-symbol returns Str {
        $.int.Str
    }

    method to-str-list returns Array[Str] {
        die "unexpected int $.int";
    }

    method to-c(Scope $scope) returns Output {
        my $tname = "t{counter}";
        output {
            .command: "LICP $tname;";
            .command: "$tname.i = {$.int.Str};";
            .return: $tname
        }
    }
}

class Symbol is Node {
    has Str $.symbol;

    method to-symbol returns Str {
        $.symbol
    }

    method to-str-list returns Array[Str] {
        Array[Str].new($.symbol.split("", :skip-empty))
    }

    method to-c(Scope $scope) returns Output {
        die "unexpected symbol $.symbol" unless $.symbol ∈ $scope.variables.keys;
        output {
            .return: "vars[{$scope.variables{$.symbol}}]"
        }
    }
}

class List is Node {
    has Node @.list;

    method to-symbol returns Str {
        die "unexpected list"
    }

    method to-str-list returns Array[Str] {
        @.list.map(*.to-symbol)
    }

    method to-c(Scope $scope) returns Output {
        my $name = @.list[0].to-symbol;
        given $name {
            when "+" {
                self!binary-operator($scope, "+")
            }
            when "-" {
                self!binary-operator($scope, "-")
            }
            when "*" {
                self!binary-operator($scope, "*")
            }
            when "/" {
                self!binary-operator($scope, "/")
            }
            when "=" {
                self!binary-operator($scope, "==")
            }
            when "<" {
                self!binary-operator($scope, "<")
            }
            when ">" {
                self!binary-operator($scope, ">")
            }
            when "if" {
                my Node $cond = @.list[1];
                my Node $then = @.list[2];
                my Node $else = @.list[3];
                my $tname = "t{counter}";
                output -> $o {
                    $o.command: "LICP $tname;";
                    $o.command: "if ($o.merge($cond.to-c($scope)).i) \{";
                    $o.command: $o.merge-header($then.to-c($scope), "$tname =");
                    $o.command: "\} else \{";
                    $o.command: $o.merge-header($else.to-c($scope), "$tname =");
                    $o.command: "\}";
                    $o.return: $tname
                }
            }
            when "λ" {
                my Str @params = @.list[1].to-str-list;
                my Node $body = @.list[2];
                my Scope $new-scope = $scope.clone;
                $new-scope.add-variable($_) for @params;
                my $fname = "f{counter}";
                my $tname = "t{counter}";
                my $n = $new-scope.variables.elems;
                my $old-n = $scope.variables.elems;
                output {
                    .header: "LICP {$fname}(LICP *vars) \{\n{.merge-header($body.to-c($new-scope), "return")}\n\}";
                    .command: "LICP $tname;";
                    .command: "$tname.f.f = &$fname;";
                    .command: "$tname.f.vars = alloc(sizeof(LICP) * $n);" if $n;
                    .command: "memcpy($tname.f.vars, vars, sizeof(LICP) * $old-n);" if $old-n;
                    .command: "$tname.f.n = $n;";
                    .return: $tname
                }
            }
            when "call" {
                my Node $func = @.list[1];
                my Node @args = @.list[2..*];
                my Str @tmp-vars;
                @tmp-vars.push("t{counter}") for ^@args;
                my $tname = "t{counter}";
                output -> $o {
                    my $fcode = $o.merge($func.to-c($scope));
                    $o.command: "LICP {$_.value} = {$fcode}.f.vars[{$fcode}.f.n-{@args.elems - $_.key}];" for @tmp-vars.pairs;
                    $o.command: "{$fcode}.f.vars[{$fcode}.f.n-{@args.elems - $_[0]}] = $o.merge($_[1].to-c($scope));" for zip ^@tmp-vars, @args;
                    $o.command: "LICP $tname = {$fcode}.f.f({$fcode}.f.vars);";
                    $o.command: "{$fcode}.f.vars[{$fcode}.f.n-{@args.elems - $_.key}] = {$_.value};" for @tmp-vars.pairs;
                    $o.return: $tname;
                }
            }
            default {
                die "unknown command $name"
            }
        }
    }

    method !binary-operator(Scope $scope, Str $op) returns Output {
        my $tname = "t{counter}";
        output -> $o {
            $o.command: "LICP $tname;";
            $o.command: "$tname.i = @.list[1..*].map(-> $e {$o.merge($e.to-c($scope)) ~ ".i"}).join($op);";
            $o.return: $tname
        }
    }
}

grammar LICP {
    token TOP                    { <ws> <expr> <ws> }
    proto token expr             { * }
    multi token expr:sym<symbol> { <symbol> }
    multi token expr:sym<list>   { <list> }
    multi token expr:sym<int>    { <int> }
    token symbol                 { <-[()\s0..9]>+ }
    token int                    { \d+ }
    token list                   { '(' <ws> <expr> [<ws> <expr>]* <ws> ')' }
}

class ToAST {
    method TOP ($/)              { make $<expr>.made }
    method expr:sym<symbol> ($/) { make Symbol.new(symbol => $<symbol>.Str) }
    method expr:sym<int> ($/)    { make IntSym.new(int => $<int>.Int) }
    method expr:sym<list> ($/)   { make $<list>.made }
    method list ($/)             { make List.new(list => $<expr>.map(*.made)) }
}

sub MAIN() {
    LICP.parse("fibonacci.licp".IO.slurp, actions => ToAST);
    say $/.ast.to-c(Scope.new(variables => {})).to-string;
}
