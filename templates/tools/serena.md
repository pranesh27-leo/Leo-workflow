# Serena — semantic code intelligence

Find a symbol, find what references it, edit it by name rather than by line
number. `find_symbol` and `find_referencing_symbols` before `grep`: they answer
what grep cannot, which is *who calls this*.

## Modes

Serena has its own modes and they line up with leo's:

| leo mode | serena |
|---|---|
| `coding`, `debugging` | `--mode editing` — symbol lookup and symbolic edits |
| everything else | `--mode planning` — read and analyse, do not edit |

## Setting a project up

**JavaScript is not a language name.** `--language javascript` fails with
*"Unknown language 'javascript'"*. Both JS and TS projects are:

```sh
serena project create --language typescript
```

Go projects are `--language go`.

## health-check

```sh
cd <project root> && serena project health-check
```

**It takes no `--project` flag.** Run it from the project root.

**It fails on the language server, not on serena.** Serena drives a language
server per language, and those are separate installs that must be on `PATH`:

| Error | Cause | Fix |
|---|---|---|
| `Go is not installed` | the Go toolchain is not on `PATH` | symlink your SDK's `go` and `gofmt` into a directory that is |
| `gopls is not installed` | gopls is a separate install from Go | `go install golang.org/x/tools/gopls@latest`, then put it on `PATH` |

leo does not install language servers. `leo install serena` installs serena;
what its language servers need is your environment, and leo does not write
there.
