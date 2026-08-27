# catalogue — library loans assistant

`catalogue` is a small agent that manages book loans for a fixed catalogue of
five titles. It is reached as a command line: `catalogue.sh <command> [args]`.

This document is the agent's specification. `rook explore` reads it to derive
the features it will then write scenarios against.

## Catalogue

| id | title | author |
|---|---|---|
| b-1 | The Left Hand of Darkness | Ursula K. Le Guin |
| b-2 | Piranesi | Susanna Clarke |
| b-3 | The Dispossessed | Ursula K. Le Guin |
| b-4 | Klara and the Sun | Kazuo Ishiguro |
| b-5 | Station Eleven | Emily St. John Mandel |

## Behaviour

### Search — `catalogue.sh search <term>`

Lists every entry whose **title or author** matches the term, case-insensitively,
each annotated with its current state (`available` or `on loan`). A term
matching nothing is not an error: the agent says so plainly and exits 0.

Searching is read-only. It must never change what is on loan.

### Borrow — `catalogue.sh borrow <id>`

Marks an available book as on loan and confirms with the book's title.

It refuses, changing nothing, when:

- the id is not in the catalogue,
- the book is already on loan,
- the borrower already holds the **borrow limit of 2** books.

Every refusal explains why, states that nothing changed, and exits 1.

### Return — `catalogue.sh return <id>`

Returns a book that is currently on loan and confirms with its title. Returning
a book that is not on loan is refused with exit 1, and changes nothing.

### Status — `catalogue.sh status`

Prints every catalogue entry as `id|title|author|state`, one per line, where
state is `available` or `on loan`. Read-only.

### Reset — `catalogue.sh reset`

Clears all loans. Intended for test setup.

## Contract

- **Exit codes** — `0` success, `1` refused (a valid request the agent declines),
  `2` usage error (missing or unknown command).
- **Refusals are safe.** A refused operation must leave state exactly as it was.
- **Confirmations name the book.** A successful borrow or return states the
  title, not only the id.
- **The borrow limit is 2** and is counted across all held books.

## Not specified

The material does not define behaviour for concurrent borrowers, reservations,
due dates, or partial-word author matching beyond plain substring matching.
