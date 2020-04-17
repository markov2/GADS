
# Full rewrite of GADS into Linkspace

**Work in progress!**

## Rename of objects

The Linkspace application resembles spreatsheets a lot, which means
we can better move towards that terminology.  Besides, a few object
names are really confusing, so we change that as well.

### New class Linkspace

This top-level object connects the major components.  They can
always find eachother via the global $::linkspace.

This object is the only which is permitted to process the user
configuration.

### New class Linkspace::DB

Manage the (DBIx::Class) schema, and simplifies often used database
queries **a lot**.  Globally available via $::db.

### New class Linkspace::Session

Manage the processing: relates a site with a user.  Globally available
via $::session.

Not (yet?) the same as the Dancer2 session().

### New class Linkspace::User

There will always be a user active in the Session: either some person
who is logged-in, a system user, or the test user.

### New class Linkspace::Site

Manages a set of Documents (currently only one supported) and
and some global company related settings.  Management of User, Group
and Permission is managed by Linkspace::Site::Users.

### New class Linkspace::Document

Every Site has one Document, which contains Sheets.  Via the document,
sheets can access other sheets.

### Class Linkspace::Sheet (was part of GADS::Instance)

The Sheets are complex, therefore their administration is split various
main components:
 - Layout, which defines the Columns which are available per Row
 - Data, which manages the data.  Searches result in Pages
 - Views, subsetting the visibility of the Sheet (search like)
 - permissions

Includes a part of GADS::Layout.

### Class Linkspace::Sheet::Layout (was part of GADS::Layout)

Manage the Columns which are available for this sheet: the configurable
fields which appear in any Row.

### Class Linkspace::Sheet::Data (was part of GADS::Records)

Manage searching in the Sheets' data, creating access to sub-sets (Pages)
of each

### Class Linkspace::Page (was part of GADS::Records)

Manage Rows with data, f.i. their versioning.  It is quite autonomous,
because it has multiple purposes.

### Class Linkspace::Sheet::Views (was GADS::Views)

Manage search results: restricted Views on the whole Sheet.

### Class Linkspace::View (was GADS::View)

Manage user search settings, based on Filters.  Applying a view will
result in Pages of sheet data.

  GADS::Alert -> Linkspace::View::Alert

### Class Linkspace::Filter (was GADS::Filter)
Stored as JSON in a view.

### Class Linkspace::Page::Row (was GADS::Record)

Each contain a list of Datums.  Each Datum relates to a Column in the
Layout.



