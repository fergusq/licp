#!/usr/bin/env perl6

my $counter = 0;
sub counter returns Int { $counter++ }

class Output {
    has Str @.header-buffer is rw;
    has Str @.command-buffer is rw;
    has Str @.command-after-let-buffer is rw;
    has Str $.expr-buffer is rw = "";

    method header(Str $s) {
        $.header-buffer.push($s ~ "\n");
    }

    method command(Str $s, Int $indent = 1) {
        $.command-buffer.push("  " x $indent ~ $s ~ "\n");
    }

    method command-after-let(Str $s, Int $indent = 1) {
        $.command-after-let-buffer.push("  " x $indent ~ $s ~ "\n");
    }

    method return(Str $s) {
        $.expr-buffer = $s;
    }

    method merge(Output $other, Int $indent = 0, Bool :$let = False) returns Str {
        @.header-buffer.append($other.header-buffer.map("  " x $indent ~ *));
        @.command-buffer.append($other.command-buffer.map("  " x $indent ~ *));
        ($let ?? $.command-after-let-buffer !! $.command-buffer)
                .append($other.command-after-let-buffer.map("  " x $indent ~ *));
        return $other.expr-buffer
    }

    method merge-header(Output $other, Str $ret, Int $indent = 0) returns Str {
        $.header-buffer.append($other.header-buffer);
        my $i = "  " x $indent;
        "{$other.command-buffer.map($i ~ *).join}  $i$ret {$other.expr-buffer};"
    }

    method after-let {
        @.command-buffer.append(@.command-after-let-buffer);
        @.command-after-let-buffer = ();
    }

    method to-string {
        "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include \"licp.h\"\n\n{$.header-buffer.join}\nint main() \{LICP *vars;\n{$.command-buffer.join}\n  // $.expr-buffer.i\n\}"
    }
}

sub output(&f) returns Output {
    my $output = Output.new();
    f($output);
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
        @.list».to-symbol
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
                self!cmp-operator($scope, "==")
            }
            when "≠" {
                self!cmp-operator($scope, "!=")
            }
            when "<" {
                self!cmp-operator($scope, "<")
            }
            when ">" {
                self!cmp-operator($scope, ">")
            }
            when "≤" {
                self!cmp-operator($scope, "<=")
            }
            when "≥" {
                self!cmp-operator($scope, ">=")
            }
            when "if" {
                self!check-args(3);
                my Node $cond = @.list[1];
                my Node $then = @.list[2];
                my Node $else = @.list[3];
                my $tname = "t{counter}";
                output -> $o {
                    $o.command: "LICP $tname;";
                    $o.command: "if ($o.merge($cond.to-c($scope)).i) \{";
                    $o.command: $o.merge-header($then.to-c($scope), "$tname =", 1), 0;
                    $o.command: "\} else \{";
                    $o.command: $o.merge-header($else.to-c($scope), "$tname =", 1), 0;
                    $o.command: "\}";
                    $o.return: $tname
                }
            }
            when "λ" {
                self!check-args(2);
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
                    .command-after-let: "memcpy($tname.f.vars, vars, sizeof(LICP) * $old-n);" if $old-n;
                    .command: "$tname.f.n = $n;";
                    .return: $tname
                }
            }
            when "call" {
                self!check-args(2, True);
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
            when "print" {
                self!check-args(1);
                my Node $arg = @.list[1];
                output -> $o {
                    $o.command: "printf(\"%d\\n\", {$o.merge($arg.to-c($scope))}.i);";
                    $o.return: "(LICP) 0"
                }
            }
            when "," {
                self!check-args(1, True);
                output -> $o {
                    $o.merge: .to-c($scope) for @.list[1..*-2];
                    $o.return: $o.merge(@.list[*-1].to-c($scope))
                }
            }
            when "let" {
                # FIXME
                self!check-args(2);
                die "illegal let bindings: expected list" unless @.list[1] ~~ List;
                my Pair @bindings = @.list[1].list.map: -> $binding {
                    die "illegal let binding: expected 2-list" unless $binding ~~ List and $binding.list.elems == 2;
                    $binding.list[0].to-symbol => $binding.list[1]
                };
                my $expr = @.list[2];
                my Scope $new-scope = $scope.clone;
                $new-scope.add-variable($_) for @bindings».key;
                my $n = $new-scope.variables.elems;
                my $old-n = $scope.variables.elems;
                my Str $tmp-vars = "tmp_vars{counter}";
                output -> $o {
                    $o.command: "LICP *$tmp-vars = vars;";
                    $o.command: "vars = alloc(sizeof(LICP) * $n);" if $n;
                    $o.command: "memcpy(vars, $tmp-vars, sizeof(LICP) * $old-n);" if $old-n;
                    $o.command: "vars[{$new-scope.variables{.key}}] = {$o.merge(.value.to-c($new-scope), :let)};" for @bindings;
                    $o.after-let;
                    $o.command: "\{";
                    my $val = $o.merge($expr.to-c($new-scope), 1);
                    $o.command: "\}";
                    $o.command: "vars = $tmp-vars;";
                    $o.return: $val
                }
            }
            default {
                die "unknown command $name"
            }
        }
    }

    method !binary-operator(Scope $scope, Str $op) returns Output {
        self!check-args(1, True);
        my $tname = "t{counter}";
        output -> $o {
            $o.command: "LICP $tname;";
            $o.command: "$tname.i = @.list[1..*].map(-> $e {$o.merge($e.to-c($scope)) ~ ".i"}).join($op);";
            $o.return: $tname
        }
    }

    method !cmp-operator(Scope $scope, Str $op) returns Output {
        self!check-args(2, True);
        my $tname = "t{counter}";
        output -> $o {
            my $operation = @.list[1..*]
                    .map(-> $e {$o.merge($e.to-c($scope)) ~ ".i"})
                    .rotor(2 => -1)
                    .map(*.join($op))
                    .join(" && ");
            $o.command: "LICP $tname;";
            $o.command: "$tname.i = $operation;";
            $o.return: $tname
        }
    }

    method !check-args(Int $required-count, Bool $or-more = False) {
        my Str $name = @.list[0].to-symbol;
        my Int $arg-count = @.list.elems - 1;
        if $or-more {
            die "$name/$required-count+ requires $required-count or more, not $arg-count args" if $arg-count < $required-count;
        } else {
            die "$name/$required-count requires $required-count, not $arg-count args" if $arg-count ≠ $required-count;
        }
    }
}

class Macro {
    has $.name;
    has @.params;
    has $.body;
}

grammar LICP {
    token TOP                    { [<ws> <expr>]* <ws> }
    proto token expr             { * }
    multi token expr:sym<symbol> { <symbol> }
    multi token expr:sym<list>   { <list> }
    multi token expr:sym<int>    { <int> }
    token symbol                 { <-[()\s0..9]>+ }
    token int                    { \d+ }
    token list                   { '(' <ws> <expr> [<ws> <expr>]* <ws> ')' }
}

class ToAST {
    method TOP ($/)              { make $<expr>.map(*.made) }
    method expr:sym<symbol> ($/) { make Symbol.new(symbol => $<symbol>.Str) }
    method expr:sym<int> ($/)    { make IntSym.new(int => $<int>.Int) }
    method expr:sym<list> ($/)   { make $<list>.made }
    method list ($/)             { make List.new(list => $<expr>.map(*.made)) }
}

sub MAIN(Str $input-file) {
    LICP.parse($input-file.IO.slurp, actions => ToAST);
    my $o = output -> $o {
        for $/.ast -> $tree {
            $o.merge($tree.to-c(Scope.new(variables => {})));
        }
    };
    say $o.to-string;
}
