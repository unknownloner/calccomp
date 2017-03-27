# !!! WARNING, INACTIVE & UNMAITAINED PROJECT !!!

# C Compiler, also Assembler targeting TI calcs

Edit Main.hs to change the target file and output file

C compiler is very much incomplete, but the assembler works.


## The Assembler
Assembler targets z80 processor, used by TI83+/TI84+CSE series calcs

The assembler does _NOT_ support find and replace #defines or macros,
right now #defines serve only as flags for #ifdef. You CAN define
numerical constants however like `VAL = 5` or `VAL equ 5`. bcall
is still supported, but it's hard coded in.

Labels must be defined with the syntax `LabelName:` (the ':' is required).
Nothing is space sensitive, so you can indent your labels and
instructions as much or as little as you like. The assembler also
supports the `line 1 \ line 2` syntax for writing multiple
lines on one line. The assembler can also output to TI vars,
but the var name must be defined in code (no `.varname` like brass).

Other useful knowledge (Some is for brass users only):

* `.relocate` is only an alias for `.org`
* `.` and `#` are treated the same (both start a directive)
* `.var` and `.varloc` are supported, but the only valid sizes for
`.var` are `byte`, `word`, or a numeric constant. `tvar` is not supported
* `.module` is not supported
* If a string is fed to `.dw`, it will output a '0' byte after every character.
* `.db` performs no conversions from ASCII to TI's char map

In general, the assembler is designed to be simple, and targetable
by compilers. Compilers in haskell could use this as a library
and feed a list of expressions directly into the assembler, if this code
was packaged up into a library (possible in the future). An actual
assembly programmer may want to use a more powerful assembler
like [Brass](http://www.benryves.com/products/brass).


On the TODO is better error reporting. Right now any argument errors (like ld hl,de or something)
will not be reported with a line number, although the args/instruction will
be reported to Ctrl-F with. I want to track line numbers too for those.
