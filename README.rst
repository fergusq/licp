LICP
====

LICP (Lambda calculus Intermediate language Compiler Program) is a compiler that compiles a simple low-level functional
programming language to C. Its purpose is to be an intermediate language for higher-level functional languages.

Available functions::

    Integer commands
    +/1+ - Addition
    -/1+ - Subtraction
    */1+ - Multiplication
    //1+ - Division
    =/2+ - Equality
    ≠/2+ - Inequality
    </2+ - Less than
    ≤/2+ - Less than or equal
    >/2+ - Greater than
    ≥/2+ - Greater than or equal

    List commands
    list/0+ - Creates a list object: (list values...)
    get/2 - Subscript: (get list index)
    len/1 - Length: (len list)

    Lambda commands
    λ/2 - Lambda abstraction: (λ parameter-list body)
    call/2+ - Evaluate a lambda abstraction: (call lambda arguments...)

    Other commands
    print/1 - Print a number
    if/3 - If: (if cond then else)
    let/2 - Bind variables to values: (let ((var val)...) expr)
    ,/1+ - Execute all arguments, evaluates to the last argument
