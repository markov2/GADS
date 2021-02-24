# Improvements

This page contains ideas about possible improvements.

## DisplayFilter

Most columns will not have a DisplayFilter.  We now look them up for
each column anyway.  Seperately.  The definedness of 'filter\_condition'
can be used to flag whether there is a file. Probably requires conversion
of existing instances.

## Curval

sort\_datums() for multivalued cells is really expensive.  Sometimes
even more expensive, certainly for Curval, where it may take each cell
in the sort column with a separate call from the database.  However,
there are many situations where it is not that bad: internal columns,
datums with accidentally the same type, ...

## Code

Why are some countries in ::Code::Countries anchored with \\b and ^, but
many not?  When fixed, this count become one big regex.
Many listed countries do not exist anymore.

When you want a flag which disables alerts for a change of code, it should
become a field in the ::Calc record.  Something what means: "do not send
alerts on recalculated values".  It may be set when changing the code of
an existing column.  May add to the form "It may take some time before
a change of this field will be computed for invisible fields.  That may
limit your search answers"
